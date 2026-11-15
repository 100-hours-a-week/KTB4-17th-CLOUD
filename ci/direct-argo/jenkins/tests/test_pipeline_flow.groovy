// Execute the real Pipeline's orchestration with in-memory Jenkins/step boundaries.
// Policy validation remains real; no credentials, shell, file, network or Jenkins IO.
def loader = new GroovyClassLoader(getClass().classLoader)
loader.parseClass('package com.cloudbees.groovy.cps; @interface NonCPS {}')
['hudson.model.BooleanParameterValue', 'hudson.model.ParametersAction', 'hudson.model.StringParameterValue',
 'hudson.slaves.EnvironmentVariablesNodeProperty', 'hudson.plugins.git.util.BuildData', 'jenkins.model.Jenkins',
 'jenkins.scm.api.SCMRevisionAction', 'org.jenkinsci.plugins.github_branch_source.GitHubSCMSource',
 'org.jenkinsci.plugins.workflow.cps.EnvActionImpl', 'org.jenkinsci.plugins.workflow.job.WorkflowJob',
 'org.jenkinsci.plugins.workflow.multibranch.BranchJobProperty'].each { String name ->
    int split = name.lastIndexOf('.')
    loader.parseClass('package ' + name.substring(0, split) + '; class ' + name.substring(split + 1) + ' {}')
}
loader.parseClass('package hudson.model; class Cause { static class UpstreamCause {} }')
loader.parseClass('package hudson.model; class Result { static final Result SUCCESS = new Result() }')
loader.parseClass('package jenkins.plugins.git; class AbstractGitSCMSource { static class SCMRevisionImpl {} }')
File base = new File(args[0])
String assembled = new File(base, 'coordinator-pipeline.groovy').getText('UTF-8').replace('/* COORDINATOR_POLICY */',
        new File(base, 'CoordinatorPolicy.groovy').getText('UTF-8'))
Class pipeline = loader.parseClass(assembled, 'FlowCoordinator.groovy')
Class policy = loader.loadClass('CoordinatorPolicy')
String oldSha = 'a' * 40, newSha = 'b' * 40
for (String job in ['cd/backend-dev', 'cd/ai-dev', 'cd/backend-main', 'cd/ai-main']) {
    for (String mode in ['publish', 'reuse', 'loop', 'failed', 'missing-cause', 'changed-artifact', 'shadow', 'wrong-job', 'prior-coordinator-build', 'reuse-existing', 'reuse-mismatch', 'reuse-artifacts-missing']) {
        Map profile = policy.profile(job)
        List events = [], shell = [], writes = [], requested = [], envCalls = [], archived = []
        Map environment = [:]
        Map current = [fullProjectName:job, number:20]
        String stage = ''
        boolean allowed = true
        boolean nodeHeld = false
        Closure pendingSteps = null, pendingPost = null
        def source = { int number, String sha, boolean push, boolean own ->
            [source_job:profile.source_job, build_number:number, source_sha:sha, branch:profile.source_branch,
             result:'SUCCESS', is_building:false, configured_repository:profile.source_repository,
             coordinator_build_numbers:own ? [mode == 'prior-coordinator-build' ? 19 : 20] : [],
             parameters:[PUSH_IMAGE:[type:'boolean', value:push]], called_by_coordinator:own,
             derived_environment:profile.family == 'be' ? [DEPLOYMENT_REQUESTED:'false', STAGING_REQUESTED:'false',
                PRODUCTION_REQUESTED:'false', PUBLICATION_REQUESTED:push.toString()] :
                [AUTO_DEPLOY:'false', MANUAL_GITOPS_PR:'false', PUBLISH_IMAGE:push.toString()],
             scm_evidence:[[kind:'SCMRevisionAction', source_repository:profile.source_repository,
                            source_sha:sha, branch:profile.source_branch]]]
        }
        Script script = (Script) pipeline.newInstance()
        script.metaClass.assertLegacyDeploymentDisabled = { events.add('flags'); [:] }
        script.metaClass.selectInitialRun = { Map p, int n ->
            policy.selectInitial(p, [source(8, oldSha, mode == 'reuse', mode == 'loop')])
        }
        script.metaClass.snapshotRun = { Map p, int n ->
            assert n == 9
            source(9, newSha, true, mode != 'missing-cause')
        }
        script.metaClass.findReusablePublisher = { Map p, String sha ->
            assert sha == oldSha
            if (mode in ['reuse-existing', 'reuse-mismatch', 'reuse-artifacts-missing']) {
                Map published = policy.validateRun(p, source(7, mode == 'reuse-mismatch' ? newSha : oldSha, true, false), true)
                return [publisher:published, scanned:4, scan_limit:50]
            }
            return [publisher:null, scanned:3, scan_limit:50]
        }
        script.metaClass.exactArtifacts = { Map p, int n ->
            events.add('artifacts:' + n)
            if (mode == 'reuse-artifacts-missing') throw new IllegalArgumentException('Selected publisher artifact disappeared')
            assert n == (mode == 'reuse' ? 8 : mode == 'reuse-existing' ? 7 : 9)
            Map receipt = policy.validateRun(p, source(n, mode in ['reuse', 'reuse-existing'] ? oldSha : newSha, true, true), true)
            if (mode == 'changed-artifact') receipt.source_commit = 'c' * 40
            [receipt:receipt, files:['image-digest.txt':'ZGlnaWVzdA==']]
        }
        Map steps = [currentBuild:current, env:environment, none:'none']
        steps.pipeline = { Closure c -> c.call() }
        steps.environment = { Closure c ->
            c.delegate = environment; c.resolveStrategy = Closure.DELEGATE_FIRST; c.call()
            environment.keySet().toList().each { environment[it] = environment[it].toString() }
        }
        steps.options = { Closure ignored -> }
        steps.triggers = { Closure ignored -> }
        steps.stages = { Closure c -> c.call() }
        steps.stage = { String name, Closure c ->
            stage = name; allowed = true; nodeHeld = false; pendingSteps = null; pendingPost = null
            c.call()
            try { if (allowed) pendingSteps?.call() }
            finally { if (allowed) pendingPost?.call() }
        }
        steps.when = { Closure c -> c.call() }
        steps.beforeAgent = { boolean ignored -> }
        steps.expression = { Closure c -> allowed = c.call() }
        steps.agent = { Object c -> if (c instanceof Closure && allowed) { nodeHeld = true; c.call() } }
        steps.label = { String ignored -> }
        steps.steps = { Closure c -> pendingSteps = c }
        steps.script = { Closure c -> c.call() }
        steps.post = { Closure c -> pendingPost = c }
        steps.always = { Closure c -> c.call() }
        steps.timeout = { Map values, Closure c -> c.call() }
        steps.booleanParam = { Map values -> values }
        steps.build = { Map values ->
            assert !nodeHeld: 'Producer wait held the single executor'
            assert values.job == '/' + profile.source_job && values.wait && !values.propagate
            Map params = values.parameters.collectEntries { [(it.name):it.value] }
            assert params.PUSH_IMAGE == true
            assert params.findAll { it.key != 'PUSH_IMAGE' }.every { it.value == false }
            assert params.keySet() == (profile.family == 'be' ?
                ['PUSH_IMAGE','DEPLOY_STAGING','DEPLOY_PRODUCTION','PREPARE_PROD_RELEASE'] as Set :
                ['PUSH_IMAGE','CREATE_GITOPS_PR'] as Set)
            requested.add(params); events.add('producer')
            [number:9, fullProjectName:mode == 'wrong-job' ? 'cd/' + profile.source_job : profile.source_job,
             result:mode == 'failed' ? 'FAILURE' : 'SUCCESS']
        }
        steps.withEnv = { List values, Closure c -> envCalls.add(values.collect { it.toString() }); c.call() }
        steps.sh = { String command -> assert nodeHeld; shell.add(command) }
        steps.writeFile = { Map values -> writes.add(values); events.add('write:' + values.file) }
        steps.deleteDir = { -> events.add('delete') }
        steps.archiveArtifacts = { Map values -> archived.add(values); events.add('archive') }
        steps.usernamePassword = { Map values -> assert values.credentialsId == 'github-app-star23'; values }
        steps.withCredentials = { List values, Closure c -> c.call() }
        steps.echo = { Object ignored -> }
        steps.error = { String message -> throw new IllegalStateException(message) }
        script.binding = new Binding(steps)
        Throwable caught = null
        try { script.run() } catch (RuntimeException error) { caught = error }
        if (mode == 'loop') {
            assert current.result == 'NOT_BUILT' && requested.isEmpty() && shell.isEmpty() && writes.isEmpty()
        } else if (mode in ['failed', 'missing-cause', 'changed-artifact', 'wrong-job', 'prior-coordinator-build', 'reuse-mismatch', 'reuse-artifacts-missing']) {
            assert caught != null: 'Failed producer or altered exact-Run evidence reached deployment'
            assert shell.isEmpty(): 'Failed producer caused a shell/deployment step'
            if (mode == 'reuse-artifacts-missing') {
                assert writes.any { it.file == 'publisher-selection.json' }
                assert archived.size() == 1 && archived[0].artifacts.split(',').contains('publisher-selection.json')
                assert events.indexOf('write:publisher-selection.json') < events.indexOf('artifacts:7')
                assert events.indexOf('archive') < events.lastIndexOf('delete')
            }
        } else {
            assert caught == null
            assert requested.size() == (mode in ['reuse', 'reuse-existing'] ? 0 : 1)
            assert shell.size() == 2 && archived.size() == 1
            assert archived[0].artifacts.split(',').contains('publisher-selection.json')
            assert envCalls[0].contains('CD_ENVIRONMENT=' + profile.environment)
            assert envCalls[0].contains('CD_SOURCE_BRANCH=' + profile.source_branch)
            assert envCalls[0].contains('CD_SOURCE_SHA=' + (mode in ['reuse', 'reuse-existing'] ? oldSha : newSha))
            assert envCalls[0].contains('KUBECTL=/opt/star23-staging-cd/bin/kubectl')
            assert shell[0].contains('/opt/star23-direct-cd/validate_upstream.py')
            assert shell[1].contains('/opt/star23-direct-cd/deploy_release.py')
            assert shell[1].contains('--release-file verified-release.json')
            assert shell[1].contains('--source-branch "$CD_SOURCE_BRANCH"')
            assert !shell[1].contains('--digest-file') && !shell[1].contains('dev-')
            Map evidence = new groovy.json.JsonSlurper().parseText(writes.find { it.file == 'publisher-selection.json' }.text)
            assert evidence.trigger.run_id == profile.source_job + '#8'
            assert evidence.publisher.run_id == profile.source_job + (mode == 'reuse' ? '#8' : mode == 'reuse-existing' ? '#7' : '#9')
            assert evidence.mode == (mode == 'reuse' ? 'trigger-published' : mode == 'reuse-existing' ? 'reuse-exact-sha' : 'requested-new-publisher')
            if (mode == 'reuse-existing') assert evidence.trigger.source_commit == evidence.publisher.source_commit
            assert current.description.startsWith(profile.environment + ' ' + profile.family + ' deployed')
        }
    }
}
println 'Pipeline flow checks passed: four profiles, no executor wait, exact producer, loop and failure suppression'
