import com.cloudbees.groovy.cps.NonCPS
import groovy.json.JsonOutput
import hudson.model.BooleanParameterValue
import hudson.model.Cause
import hudson.model.ParametersAction
import hudson.model.Result
import hudson.model.StringParameterValue
import hudson.slaves.EnvironmentVariablesNodeProperty
import hudson.plugins.git.util.BuildData
import jenkins.model.Jenkins
import jenkins.scm.api.SCMRevisionAction
import jenkins.plugins.git.AbstractGitSCMSource
import org.jenkinsci.plugins.github_branch_source.GitHubSCMSource
import org.jenkinsci.plugins.workflow.cps.EnvActionImpl
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.multibranch.BranchJobProperty

/* COORDINATOR_POLICY */

@NonCPS
Map assertLegacyDeploymentDisabled() {
    Map flags = [:]
    Jenkins.get().globalNodeProperties.findAll { it instanceof EnvironmentVariablesNodeProperty }.each { property ->
        ['STAR23_AUTO_DEPLOY_STAGING', 'AI_STAGING_AUTO_DEPLOY_ENABLED',
         'STAR23_AUTO_DEPLOY_PROD', 'AI_PROD_AUTO_DEPLOY_ENABLED'].each { name ->
            if (property.envVars.containsKey(name)) {
                if (flags.containsKey(name)) throw new IllegalArgumentException('Duplicate global deployment flag')
                flags[name] = property.envVars[name]
            }
        }
    }
    return CoordinatorPolicy.checkFlags(flags)
}

/** No Run, SCM object, credential, stream, or Jenkins object leaves this method. */
@NonCPS
Map snapshotRun(Map profile, int number) {
    WorkflowJob job = Jenkins.get().getItemByFullName(profile.source_job, WorkflowJob.class)
    if (job == null) throw new IllegalArgumentException('The fixed source WorkflowJob is missing')
    def branch = job.getProperty(BranchJobProperty.class)?.getBranch()
    def source = branch == null ? null : job.parent.getSCMSource(branch.sourceId)
    if (branch?.name != profile.source_branch || !(source instanceof GitHubSCMSource) ||
            source.repoOwner + '/' + source.repository != profile.source_repository) {
        throw new IllegalArgumentException('The original fixed-branch SCM configuration does not match the fixed source repository')
    }
    def run = job.getBuildByNumber(number)
    if (run == null) throw new IllegalArgumentException('The exact upstream Run no longer exists')
    Map parameters = [:]
    List parameterActions = run.getActions(ParametersAction.class)
    parameterActions.each { action ->
        action.parameters.each { parameter ->
            if (parameters.containsKey(parameter.name)) throw new IllegalArgumentException('Duplicate upstream parameter')
            if (parameter instanceof BooleanParameterValue) {
                parameters[parameter.name] = [type:'boolean', value:parameter.value]
            } else if (parameter instanceof StringParameterValue) {
                parameters[parameter.name] = [type:'string', value:parameter.value]
            } else {
                throw new IllegalArgumentException('Unsupported upstream parameter type')
            }
        }
    }
    Map environment = run.getAction(EnvActionImpl.class)?.getOverriddenEnvironment() ?: [:]
    String sha = profile.family == 'be' ? environment.SOURCE_COMMIT : environment.GIT_COMMIT
    if (environment.SOURCE_COMMIT && environment.GIT_COMMIT && environment.SOURCE_COMMIT != environment.GIT_COMMIT) {
        throw new IllegalArgumentException('Upstream source SHA fields disagree')
    }
    List evidence = []
    List revisionActions = run.getActions(SCMRevisionAction.class)
    if (revisionActions.size() > 1) throw new IllegalArgumentException('Ambiguous source SCMRevisionAction')
    def revisionAction = revisionActions.isEmpty() ? null : revisionActions[0]
    String revisionSourceId = revisionAction?.getSourceId()
    if (revisionSourceId != null && revisionSourceId != branch.sourceId) {
        throw new IllegalArgumentException('SCMRevisionAction belongs to a different configured source')
    }
    def revision = revisionAction?.getRevision()
    boolean legacyRevision = revision != null && revisionSourceId == null
    boolean boundBuildData = false
    if (revision != null) {
        String hash
        if (revision instanceof AbstractGitSCMSource.SCMRevisionImpl) hash = revision.getHash()
        else throw new IllegalArgumentException('Unsupported upstream SCM revision type')
        evidence.add([kind:'SCMRevisionAction', source_repository:profile.source_repository,
                      source_sha:hash, branch:revision.head.name])
    }
    Set allowedUrls = ['https://github.com/' + profile.source_repository,
                       'https://github.com/' + profile.source_repository + '.git',
                       'git@github.com:' + profile.source_repository + '.git'] as Set
    List matching = run.getActions(BuildData.class).findAll { data ->
        data.getRemoteUrls().any { allowedUrls.contains(it) }
    }
    if (matching.size() > 1) throw new IllegalArgumentException('Ambiguous source BuildData')
    if (matching.size() == 1) {
        def data = matching[0]
        if (!allowedUrls.containsAll(data.getRemoteUrls())) {
            throw new IllegalArgumentException('Mixed source remote URLs are not permitted')
        }
        def built = data.getLastBuiltRevision()
        String hash = built?.getSha1String()
        List branchProof = (built?.getBranches() ?: []).collect { item -> [name:item.name, sha:item.getSHA1String()] }
        // Detached checkout BuildData is useful for hash agreement when the
        // concrete SCMRevisionAction already proves the exact branch.
        if (branchProof && branchProof.every { it.name == 'HEAD' } && revision != null && !legacyRevision) {
            if (hash != sha) throw new IllegalArgumentException('Detached BuildData SHA disagrees with source revision')
        } else {
            evidence.add(CoordinatorPolicy.buildDataProof(profile, hash, branchProof))
            boundBuildData = true
        }
    }
    if (legacyRevision && !boundBuildData) {
        throw new IllegalArgumentException('Legacy SCMRevisionAction requires independent repository and branch-bound BuildData')
    }
    Map derived = [:]
    List expectedNames = profile.family == 'be' ?
            ['DEPLOYMENT_REQUESTED', 'STAGING_REQUESTED', 'PRODUCTION_REQUESTED', 'PUBLICATION_REQUESTED'] :
            ['AUTO_DEPLOY', 'MANUAL_GITOPS_PR', 'PUBLISH_IMAGE']
    expectedNames.each { name -> derived[name] = environment[name] }
    List coordinatorBuilds = run.causes.findAll { cause ->
        cause instanceof Cause.UpstreamCause && cause.upstreamProject == profile.coordinator
    }.collect { cause -> cause.upstreamBuild }
    return [source_job:job.fullName, build_number:run.number, result:run.result?.toString(),
            is_building:run.isBuilding(), branch:branch.name, configured_repository:profile.source_repository,
            source_sha:sha, parameters:parameters, derived_environment:derived, scm_evidence:evidence,
            called_by_coordinator:!coordinatorBuilds.isEmpty(), coordinator_build_numbers:coordinatorBuilds]
}

@NonCPS
Map selectInitialRun(Map profile, int coordinatorNumber) {
    WorkflowJob job = Jenkins.get().getItemByFullName(profile.coordinator, WorkflowJob.class)
    def run = job?.getBuildByNumber(coordinatorNumber)
    if (run == null) throw new IllegalArgumentException('The current coordinator Run is missing')
    List numbers = []
    run.causes.each { cause ->
        if (!(cause instanceof Cause.UpstreamCause) || cause.upstreamProject != profile.source_job) {
            throw new IllegalArgumentException('Only an exact fixed-branch upstream SUCCESS trigger is accepted')
        }
        if (cause.upstreamBuild <= 0) throw new IllegalArgumentException('Invalid upstream build number')
        numbers.add(cause.upstreamBuild)
    }
    List snapshots = numbers.unique().collect { number -> snapshotRun(profile, number as int) }
    return CoordinatorPolicy.selectInitial(profile, snapshots)
}

@NonCPS
Map exactArtifacts(Map profile, int number) {
    Map receipt = CoordinatorPolicy.validateRun(profile, snapshotRun(profile, number), true)
    WorkflowJob job = Jenkins.get().getItemByFullName(profile.source_job, WorkflowJob.class)
    def run = job.getBuildByNumber(number)
    def root = run.getArtifactManager().root()
    Map files = [:]
    profile.artifacts.each { String archivePath, String localName ->
        def artifact = root.child(archivePath)
        if (!artifact.isFile()) throw new IllegalArgumentException('A required exact-Run image artifact is missing')
        InputStream input = artifact.open()
        try {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream()
            byte[] buffer = new byte[8192]
            int count
            while ((count = input.read(buffer)) != -1) {
                if (bytes.size() + count > 128 * 1024) throw new IllegalArgumentException('An image artifact exceeds 128 KiB')
                bytes.write(buffer, 0, count)
            }
            if (bytes.size() == 0) throw new IllegalArgumentException('An image artifact is empty')
            files[localName] = Base64.encoder.encodeToString(bytes.toByteArray())
        } finally {
            input.close()
        }
    }
    return [receipt:receipt, files:files]
}

/** Newest bounded same-job search. No Jenkins Run or artifact bytes leave this method. */
@NonCPS
Map findReusablePublisher(Map profile, String sourceCommit) {
    if (!(sourceCommit ==~ /[0-9a-f]{40}/)) throw new IllegalArgumentException('A full trigger source SHA is required')
    WorkflowJob job = Jenkins.get().getItemByFullName(profile.source_job, WorkflowJob.class)
    if (job == null) throw new IllegalArgumentException('The fixed source WorkflowJob is missing')
    int scanned = 0
    def run = job.getLastBuild()
    while (run != null && scanned < 50) {
        scanned++
        if (!run.isBuilding() && run.result == Result.SUCCESS) {
            try {
                Map candidate = CoordinatorPolicy.validateRun(profile, snapshotRun(profile, run.number as int), true)
                if (candidate.source_commit == sourceCommit) {
                    // Existence and bounded-size evidence check on this exact Run.
                    // Semantic contents are checked by the protected normalizer on
                    // the agent, then independently by the deployment helper.
                    Map transport = exactArtifacts(profile, run.number as int)
                    if (transport.receipt.source_commit != sourceCommit) {
                        throw new IllegalArgumentException('Publisher source changed during artifact validation')
                    }
                    return [publisher:transport.receipt, scanned:scanned, scan_limit:50]
                }
            } catch (IllegalArgumentException rejected) {
                // Invalid/unpublished/foreign/incomplete candidates are ineligible.
                // Do not expose artifact content or arbitrary exception text.
            }
        }
        run = run.getPreviousBuild()
    }
    return [publisher:null, scanned:scanned, scan_limit:50]
}

@NonCPS
Map selectionRunEvidence(Map receipt) {
    List fields = ['source_job','build_number','run_id','source_commit','source_branch','environment','result','push_image']
    return receipt.findAll { key, value -> key in fields }
}

@NonCPS
void assertAiLocalEnabled(Map profile, Object staging, Object prod) {
    if (profile.family == 'ai') {
        Object value = profile.environment == 'staging' ? staging : prod
        if (!(value instanceof String) || value != 'true') {
            throw new IllegalArgumentException('AI direct CD requires its environment-specific job-local enable flag')
        }
    }
}

def profile = CoordinatorPolicy.profile(currentBuild.fullProjectName)
def selected = [:]
def producer = [:]
def publisherSelection = [:]

pipeline {
    agent none
    environment {
        // Job-local direct-CD gates. Build requests below pass only CI parameters.
        AI_STAGING_AUTO_DEPLOY_ENABLED = "${profile.family == 'ai' && profile.environment == 'staging' ? 'true' : 'false'}"
        AI_PROD_AUTO_DEPLOY_ENABLED = "${profile.family == 'ai' && profile.environment == 'prod' ? 'true' : 'false'}"
    }
    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timeout(time: 180, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr:'30', artifactNumToKeepStr:'30'))
    }
    triggers {
        upstream(upstreamProjects: "/${profile.source_job}", threshold:hudson.model.Result.SUCCESS)
    }
    stages {
        stage('Validate exact upstream') {
            steps {
                script {
                    assertAiLocalEnabled(profile, env.AI_STAGING_AUTO_DEPLOY_ENABLED, env.AI_PROD_AUTO_DEPLOY_ENABLED)
                    assertLegacyDeploymentDisabled()
                    selected = selectInitialRun(profile, currentBuild.number as int)
                    if (selected.skip) {
                        currentBuild.result = 'NOT_BUILT'
                        echo selected.reason
                    } else {
                        currentBuild.description = "${profile.family} ${selected.source_commit.take(12)} from #${selected.build_number}"
                    }
                }
            }
        }
        stage('Obtain exact checked image build') {
            when { expression { !selected.skip } }
            steps {
                script {
                    assertAiLocalEnabled(profile, env.AI_STAGING_AUTO_DEPLOY_ENABLED, env.AI_PROD_AUTO_DEPLOY_ENABLED)
                    assertLegacyDeploymentDisabled()
                    publisherSelection = [schema_version:1, coordinator_job:profile.coordinator,
                        coordinator_build_number:currentBuild.number as int, trigger:selectionRunEvidence(selected)]
                    if (selected.push_image) {
                        producer = selected
                        publisherSelection.mode = 'trigger-published'
                    } else {
                        Map reusable = findReusablePublisher(profile, selected.source_commit)
                        publisherSelection.scan = [scanned:reusable.scanned, limit:reusable.scan_limit]
                        if (reusable.publisher) {
                            if (reusable.publisher.source_commit != selected.source_commit) {
                                error('Reusable publisher does not match the exact triggering source SHA')
                            }
                            producer = reusable.publisher
                            publisherSelection.mode = 'reuse-exact-sha'
                        } else {
                            publisherSelection.mode = 'requested-new-publisher'
                            def requested = profile.family == 'be' ? [
                                booleanParam(name:'PUSH_IMAGE', value:true), booleanParam(name:'DEPLOY_STAGING', value:false),
                                booleanParam(name:'DEPLOY_PRODUCTION', value:false), booleanParam(name:'PREPARE_PROD_RELEASE', value:false)
                            ] : [booleanParam(name:'PUSH_IMAGE', value:true), booleanParam(name:'CREATE_GITOPS_PR', value:false)]
                            // No node/agent is held while this existing CI job uses the single executor.
                            def imageBuild = build(job:'/' + profile.source_job, parameters:requested, wait:true, propagate:false)
                            if (imageBuild.result != 'SUCCESS') {
                                error("Image build ${profile.source_job}#${imageBuild.number} finished ${imageBuild.result}; the environment was not deployed")
                            }
                            if (imageBuild.fullProjectName != profile.source_job) error('Returned image producer is not the fixed source job')
                            Map exactProducer = snapshotRun(profile, imageBuild.number as int)
                            if (!(exactProducer.coordinator_build_numbers instanceof List) ||
                                    !exactProducer.coordinator_build_numbers.contains(currentBuild.number as int)) {
                                error('Image producer lacks the exact current coordinator Run cause')
                            }
                            producer = CoordinatorPolicy.validateRun(profile, exactProducer, true)
                            if (!producer.called_by_coordinator) error('Image producer lacks the expected coordinator cause')
                        }
                    }
                    publisherSelection.publisher = selectionRunEvidence(producer)
                    publisherSelection.same_source_commit = producer.source_commit == selected.source_commit
                    if (producer.source_commit != selected.source_commit) {
                        echo 'The image build validated a newer source revision; its exact Run is the deployment candidate'
                    }
                    currentBuild.description = "${profile.family} ${producer.source_commit.take(12)} image #${producer.build_number}"
                }
            }
        }
        stage('Deploy verified environment image') {
            when { beforeAgent true; expression { !selected.skip } }
            agent { label 'linux && docker' }
            steps {
                // Agent queueing is covered by the 180-minute global timeout;
                // the deployment deadline begins only after an executor exists.
                timeout(time: 20, unit:'MINUTES') {
                script {
                    assertAiLocalEnabled(profile, env.AI_STAGING_AUTO_DEPLOY_ENABLED, env.AI_PROD_AUTO_DEPLOY_ENABLED)
                    assertLegacyDeploymentDisabled()
                    deleteDir()
                    writeFile(file:'publisher-selection.json', text:JsonOutput.toJson(publisherSelection) + '\n')
                    Map transport = exactArtifacts(profile, producer.build_number as int)
                    if (transport.receipt.source_commit != producer.source_commit) error('Image source SHA changed')
                    transport.files.each { String name, String encoded ->
                        writeFile(file:'input/' + name, text:encoded, encoding:'Base64')
                    }
                    writeFile(file:'input/upstream-validation.json', text:JsonOutput.toJson(transport.receipt) + '\n')
                    transport = null
                    withEnv(["CD_FAMILY=${profile.family}", "CD_SOURCE_SHA=${producer.source_commit}",
                             "CD_ENVIRONMENT=${profile.environment}", "CD_SOURCE_BRANCH=${profile.source_branch}",
                             'KUBECTL=/opt/star23-staging-cd/bin/kubectl']) {
                        sh '''#!/bin/bash
set +x
set -euo pipefail
python3 -B /opt/star23-direct-cd/validate_upstream.py --family "$CD_FAMILY" \
  --environment "$CD_ENVIRONMENT" --source-branch "$CD_SOURCE_BRANCH" \
  --input-dir input --output-file verified-release.json
'''
                        withCredentials([usernamePassword(credentialsId:'github-app-star23',
                            usernameVariable:'SOURCE_APP_ID', passwordVariable:'SOURCE_TOKEN')]) {
                            sh '''#!/bin/bash
set +x
set -euo pipefail
python3 -B /opt/star23-direct-cd/deploy_release.py --family "$CD_FAMILY" \
  --environment "$CD_ENVIRONMENT" --source-branch "$CD_SOURCE_BRANCH" --source-commit "$CD_SOURCE_SHA" \
  --release-file verified-release.json --output-file deployment.json --execute
'''
                        }
                    }
                    currentBuild.description = "${profile.environment} ${profile.family} deployed ${producer.source_commit.take(12)}"
                }
                }
            }
            post {
                always {
                    // Raw upstream artifact content is not re-published by this trusted job.
                    archiveArtifacts(artifacts:'input/upstream-validation.json,publisher-selection.json,verified-release.json,deployment.json,deployment.commit.json', allowEmptyArchive:true)
                    deleteDir()
                }
            }
        }
    }
}
