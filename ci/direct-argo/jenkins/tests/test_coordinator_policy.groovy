// Run with Groovy 2.4+; no Jenkins instance, credentials or network are used.
def loader = new GroovyClassLoader(getClass().classLoader)
loader.parseClass('package com.cloudbees.groovy.cps; @interface NonCPS {}')
File source = new File(args[0], 'CoordinatorPolicy.groovy')
assert source.isFile(): 'Coordinator policy is not implemented yet'
Class policy = loader.parseClass(source)
String sha = 'a' * 40
def failure = { Closure body ->
    boolean rejected = false
    try { body.call() } catch (IllegalArgumentException expected) { rejected = true }
    assert rejected: 'Unsafe input was accepted'
}
def raw = { String family, int number = 8, boolean push = false, boolean own = false, String branch = 'dev' ->
    Map p = policy.profile('cd/' + (family == 'be' ? 'backend-' : 'ai-') + branch)
    [source_job: p.source_job, build_number: number, result: 'SUCCESS', is_building: false,
     branch: branch, configured_repository: p.source_repository, source_sha: sha,
     parameters: [PUSH_IMAGE: [type: 'boolean', value: push]], called_by_coordinator: own,
     derived_environment: family == 'be' ? [DEPLOYMENT_REQUESTED:'false', STAGING_REQUESTED:'false',
         PRODUCTION_REQUESTED:'false', PUBLICATION_REQUESTED:push.toString()] :
         [AUTO_DEPLOY:'false', MANUAL_GITOPS_PR:'false', PUBLISH_IMAGE:push.toString()],
     scm_evidence:[[kind:'SCMRevisionAction', source_repository:p.source_repository,
                    source_sha:sha, branch:branch]]]
}

for (String family in ['be', 'ai']) {
    for (String branch in ['dev', 'main']) {
        Map profile = policy.profile('cd/' + (family == 'be' ? 'backend-' : 'ai-') + branch)
        assert profile.source_branch == branch
        assert profile.environment == (branch == 'dev' ? 'staging' : 'prod')
        Map checked = policy.validateRun(profile, raw(family, 8, true, false, branch), true)
        assert checked.schema_version == 2 && checked.source_commit == sha
        assert checked.environment == profile.environment
        assert policy.selectInitial(profile, [raw(family, 8, false, false, branch), raw(family, 9, true, true, branch)]).build_number == 8
        assert policy.selectInitial(profile, [raw(family, 9, true, true, branch)]).skip
        failure { policy.validateRun(profile, raw(family, 8, true, false, branch == 'dev' ? 'main' : 'dev'), true) }
    }
    Map p = policy.profile(family == 'be' ? 'cd/backend-dev' : 'cd/ai-dev')
    assert policy.validateRun(p, raw(family), false).push_image == false
    assert policy.validateRun(p, raw(family, 9, true), true).source_commit == sha
    failure { policy.validateRun(p, raw(family), true) }
    Map selected = policy.selectInitial(p, [raw(family, 8), raw(family, 9, true, true)])
    assert selected.build_number == 8: 'CD-generated build recursively became a new release'
    assert policy.selectInitial(p, [raw(family, 9, true, true)]).skip == true
    // Coalesced upstream causes must not lose a later legitimate dev success.
    assert policy.selectInitial(p, [raw(family, 8), raw(family, 9, true, true), raw(family, 10)]).build_number == 10
    Map bad = raw(family, 10, true)
    bad.result = 'FAILURE'
    failure { policy.validateRun(p, bad, true) }
    bad = raw(family, 10, true); bad.source_sha = 'b' * 40
    failure { policy.validateRun(p, bad, true) }
    bad = raw(family, 10, true); bad.scm_evidence = []
    failure { policy.validateRun(p, bad, true) }
    bad = raw(family, 10, true); bad.scm_evidence[0].source_repository = 'foreign/repo'
    failure { policy.validateRun(p, bad, true) }
    bad = raw(family, 10, true); bad.source_job = 'ci/backend/main'
    failure { policy.validateRun(p, bad, true) }
    bad = raw(family, 10, true); bad.branch = 'main'
    failure { policy.validateRun(p, bad, true) }
    bad = raw(family, 10, true); bad.is_building = true
    failure { policy.validateRun(p, bad, true) }
    bad = raw(family, 10, true); bad.parameters.PUSH_IMAGE = [type:'string', value:'true']
    failure { policy.validateRun(p, bad, true) }
    bad = raw(family, 10, true); bad.parameters.EXTRA = [type:'string', value:'do not accept']
    failure { policy.validateRun(p, bad, true) }
    bad = raw(family, 10, true)
    bad.parameters[family == 'be' ? 'DEPLOY_STAGING' : 'CREATE_GITOPS_PR'] = [type:'boolean', value:true]
    failure { policy.validateRun(p, bad, true) }
    bad = raw(family, 10, true)
    bad.derived_environment[family == 'be' ? 'DEPLOYMENT_REQUESTED' : 'AUTO_DEPLOY'] = 'true'
    failure { policy.validateRun(p, bad, true) }
}
for (String branch in ['dev', 'main']) {
    Map p = policy.profile('cd/backend-' + branch)
    assert policy.buildDataProof(p, sha, [[name:'origin/' + branch, sha:sha]]).branch == branch
    assert policy.buildDataProof(p, sha, [[name:'refs/remotes/origin/' + branch, sha:sha]]).source_sha == sha
    failure { policy.buildDataProof(p, sha, []) }
    failure { policy.buildDataProof(p, sha, [[name:'origin/foreign', sha:sha]]) }
    failure { policy.buildDataProof(p, sha, [[name:'origin/' + branch, sha:'b' * 40]]) }
    failure { policy.buildDataProof(p, sha, [[name:'origin/' + branch, sha:sha], [name:'origin/other', sha:sha]]) }
}
assert policy.checkFlags([:]).size() == 4
assert policy.checkFlags([STAR23_AUTO_DEPLOY_STAGING:' false ', AI_STAGING_AUTO_DEPLOY_ENABLED:'FALSE',
                         STAR23_AUTO_DEPLOY_PROD:'false']).STAR23_AUTO_DEPLOY_PROD == 'false'
failure { policy.checkFlags([STAR23_AUTO_DEPLOY_PROD:'true']) }
failure { policy.checkFlags([AI_PROD_AUTO_DEPLOY_ENABLED:'true']) }
failure { policy.checkFlags([STAR23_AUTO_DEPLOY_STAGING:'true']) }
failure { policy.checkFlags([AI_STAGING_AUTO_DEPLOY_ENABLED:'true']) }
failure { policy.profile('cd/backend-prod') }
println 'Coordinator policy: loop, coalescing, provenance, parameter and flag checks passed'
