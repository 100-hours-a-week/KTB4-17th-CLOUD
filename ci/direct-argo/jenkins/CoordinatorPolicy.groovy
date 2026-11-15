import com.cloudbees.groovy.cps.NonCPS

/** Pure checks; the trusted Pipeline adapts Jenkins objects to these plain maps. */
class CoordinatorPolicy {
    @NonCPS
    static Map profile(String job) {
        Map profiles = ['cd/backend-dev':['be','dev'], 'cd/ai-dev':['ai','dev'],
                        'cd/backend-main':['be','main'], 'cd/ai-main':['ai','main']]
        List selected = profiles[job]
        if (selected == null) throw new IllegalArgumentException('Only the four fixed coordinator jobs are permitted')
        String family = selected[0], branch = selected[1]
        Map artifacts = family == 'be' ? [
                'release/image-digest.txt':'image-digest.txt', 'release/image-uri.txt':'image-uri.txt',
                'release/image-version.json':'image-version.json', 'release/ecr-image.json':'ecr-image.json'] : [
                '.ci-reports/image-digest.txt':'image-digest.txt', '.ci-reports/image-reference.txt':'image-reference.txt',
                '.ci-reports/image-tag.txt':'image-tag.txt', '.ci-reports/release-version.json':'release-version.json']
        return [family:family, coordinator:job, source_job:'ci/' + (family == 'be' ? 'backend/' : 'ai/') + branch,
                source_repository:'100-hours-a-week/KTB4-17th-' + (family == 'be' ? 'BE' : 'AI'),
                source_branch:branch, environment:branch == 'dev' ? 'staging' : 'prod', artifacts:artifacts]
    }

    @NonCPS
    static Map buildDataProof(Map profile, String hash, List branches) {
        Set names = [profile.source_branch, 'origin/' + profile.source_branch,
                     'refs/heads/' + profile.source_branch, 'refs/remotes/origin/' + profile.source_branch] as Set
        if (!(hash ==~ /[0-9a-f]{40}/) || branches.isEmpty() || branches.size() > 8 || branches.any { proof ->
            !(proof instanceof Map) || !names.contains(proof.name) || proof.sha != hash
        }) throw new IllegalArgumentException('BuildData does not prove the fixed source branch')
        return [kind:'BuildData', source_repository:profile.source_repository, source_sha:hash, branch:profile.source_branch]
    }

    @NonCPS
    static Map checkFlags(Map values) {
        List names = ['STAR23_AUTO_DEPLOY_STAGING', 'AI_STAGING_AUTO_DEPLOY_ENABLED',
                      'STAR23_AUTO_DEPLOY_PROD', 'AI_PROD_AUTO_DEPLOY_ENABLED']
        Map snapshot = [:]
        names.each { String name ->
            Object raw = values[name]
            if (raw != null && !(raw instanceof String)) {
                throw new IllegalArgumentException('Unexpected Jenkins activation flag type')
            }
            String value = raw == null ? null : raw.trim().toLowerCase(Locale.ROOT)
            if (!(value in [null, '', 'false'])) {
                throw new IllegalArgumentException('All source jobs must have legacy automatic GitOps deployment disabled')
            }
            snapshot[name] = raw
        }
        return snapshot
    }

    @NonCPS
    static Map validateRun(Map profile, Map run, boolean requireImage) {
        if (run.source_job != profile.source_job || !(run.build_number instanceof Integer) || run.build_number <= 0 ||
                run.result != 'SUCCESS' || run.is_building != false || run.branch != profile.source_branch ||
                run.configured_repository != profile.source_repository ||
                !(run.source_sha instanceof String) || !(run.source_sha ==~ /[0-9a-f]{40}/)) {
            throw new IllegalArgumentException('The exact upstream Run identity or result is not eligible')
        }
        Map booleans = profile.family == 'be' ?
                [PUSH_IMAGE:false, DEPLOY_STAGING:false, DEPLOY_PRODUCTION:false, PREPARE_PROD_RELEASE:false] :
                [PUSH_IMAGE:false, CREATE_GITOPS_PR:false]
        Map strings = profile.family == 'be' ?
                [CLOUD_READ_CREDENTIALS_ID:'github-app-star23-cloud-read', GITOPS_CREDENTIALS_ID:'github-app-star23-gitops'] : [:]
        if (!(run.parameters instanceof Map)) {
            throw new IllegalArgumentException('Missing typed upstream parameters')
        }
        Map resolved = new LinkedHashMap(booleans)
        run.parameters.each { Object name, Object parameter ->
            if (!(parameter instanceof Map)) throw new IllegalArgumentException('Invalid upstream parameter')
            if (booleans.containsKey(name)) {
                if (parameter.type != 'boolean' || !(parameter.value instanceof Boolean) ||
                        (name != 'PUSH_IMAGE' && parameter.value != false)) {
                    throw new IllegalArgumentException('Unsafe upstream deployment parameter')
                }
                resolved[name] = parameter.value
            } else if (strings.containsKey(name)) {
                if (parameter.type != 'string' || parameter.value != strings[name]) {
                    throw new IllegalArgumentException('Unexpected upstream credential selector')
                }
            } else {
                throw new IllegalArgumentException('Unsupported upstream parameter')
            }
        }
        boolean push = resolved.PUSH_IMAGE
        if (requireImage && !push) throw new IllegalArgumentException('The image producer did not request publication')
        Map expectedEnv = profile.family == 'be' ?
                [DEPLOYMENT_REQUESTED:'false', STAGING_REQUESTED:'false', PRODUCTION_REQUESTED:'false', PUBLICATION_REQUESTED:push.toString()] :
                [AUTO_DEPLOY:'false', MANUAL_GITOPS_PR:'false', PUBLISH_IMAGE:push.toString()]
        if (!(run.derived_environment instanceof Map) || expectedEnv.any { key, value -> run.derived_environment[key] != value }) {
            throw new IllegalArgumentException('The upstream Run was not CI/ECR-only')
        }
        if (!(run.scm_evidence instanceof List) || run.scm_evidence.isEmpty() || run.scm_evidence.size() > 8 ||
                run.scm_evidence.any { proof ->
                    !(proof instanceof Map) || !(proof.kind in ['SCMRevisionAction', 'BuildData']) ||
                    proof.source_repository != profile.source_repository || proof.source_sha != run.source_sha || proof.branch != profile.source_branch
                }) {
            throw new IllegalArgumentException('SCM provenance does not match the source SHA')
        }
        return [schema_version:2, family:profile.family, source_repository:profile.source_repository,
                source_job:profile.source_job, build_number:run.build_number,
                run_id:profile.source_job + '#' + run.build_number, result:'SUCCESS', push_image:push,
                source_branch:profile.source_branch, environment:profile.environment, source_commit:run.source_sha, scm_evidence:run.scm_evidence,
                called_by_coordinator:run.called_by_coordinator == true]
    }

    @NonCPS
    static Map selectInitial(Map profile, List runs) {
        if (runs.isEmpty()) throw new IllegalArgumentException('An exact upstream SUCCESS cause is required')
        List eligible = runs.collect { validateRun(profile, it, false) }.findAll { !it.called_by_coordinator }
        if (eligible.isEmpty()) return [skip:true, reason:'CD-generated image build completion; loop suppressed']
        return eligible.sort { a, b -> a.build_number <=> b.build_number }.last()
    }
}
