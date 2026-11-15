// Root installs this reviewed file in init.groovy.d. Do not run it from a build.
// Jenkins runs init.groovy.d after JOB_CONFIG_ADAPTED; this script never restarts Jenkins.
import groovy.json.JsonOutput
import hudson.init.InitMilestone
import hudson.model.Result
import jenkins.triggers.ReverseBuildTrigger
import org.jenkinsci.plugins.workflow.job.properties.DisableConcurrentBuildsJobProperty
import org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.PosixFilePermission
import java.security.MessageDigest
import java.util.logging.Logger
import jenkins.model.Jenkins
import org.jenkinsci.plugins.pipeline.modeldefinition.parser.Converter
import org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval
import org.jenkinsci.plugins.scriptsecurity.scripts.languages.GroovyLanguage
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition
import org.jenkinsci.plugins.workflow.job.WorkflowJob

/** Observe the installed path without clearing an operator's deliberate pause. */
void verifyInstalledCoordinator(WorkflowJob job, String expectedScript, String upstream) {
    if (job == null || !(job.definition instanceof CpsFlowDefinition) ||
            job.definition.script != expectedScript || job.definition.sandbox) {
        throw new IllegalStateException('Installed coordinator definition differs from the reviewed script')
    }
    if (job.isDisabled() || !job.isBuildable()) {
        throw new IllegalStateException('Coordinator is disabled or not buildable; operator must review and enable it explicitly: ' + job.fullName)
    }
    List properties = job.getAllProperties()
    List triggers = properties.findAll { it instanceof PipelineTriggersJobProperty }
    List concurrency = properties.findAll { it instanceof DisableConcurrentBuildsJobProperty }
    if (triggers.size() != 1 || triggers[0].triggers.size() != 1 ||
            !(triggers[0].triggers[0] instanceof ReverseBuildTrigger) ||
            triggers[0].triggers[0].upstreamProjects != '/' + upstream ||
            triggers[0].triggers[0].threshold != Result.SUCCESS) {
        throw new IllegalStateException('Coordinator requires exactly one absolute fixed-source SUCCESS reverse trigger: ' + job.fullName)
    }
    if (concurrency.size() != 1 || concurrency[0].isAbortPrevious()) {
        throw new IllegalStateException('Coordinator requires exactly one non-aborting concurrency property: ' + job.fullName)
    }
}

// Historical filename retained for reviewed installation tooling compatibility.
// This direct-CD bootstrap never schedules a build or replays historical Runs.
final String ROOT = '/opt/star23-direct-cd'
final File MARKER = new File('/var/lib/jenkins/.codex-audit/direct-cd-bootstrap.json')
Logger logger = Logger.getLogger('star23.directCd.bootstrap')
String scriptHash = 'unavailable'
String phase = 'payload'
Map state = [:]

def sha256 = { byte[] bytes -> MessageDigest.getInstance('SHA-256').digest(bytes).encodeHex().toString() }
def save = { Map value ->
    def parent = MARKER.parentFile.toPath()
    if (!Files.exists(parent)) Files.createDirectories(parent)
    if (!Files.isDirectory(parent, LinkOption.NOFOLLOW_LINKS) || Files.isSymbolicLink(parent) || Files.isSymbolicLink(MARKER.toPath())) {
        throw new IllegalStateException('Invalid marker directory')
    }
    def temp = Files.createTempFile(parent, '.direct-cd-bootstrap-', '.json')
    try {
        Files.setPosixFilePermissions(temp, [PosixFilePermission.OWNER_READ, PosixFilePermission.OWNER_WRITE] as Set)
        Files.write(temp, (JsonOutput.prettyPrint(JsonOutput.toJson(value)) + '\n').getBytes('UTF-8'))
        Files.move(temp, MARKER.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    } finally { Files.deleteIfExists(temp) }
}
def protectedPath = { String relative, long limit ->
    def path = relative == 'kubectl' ? new File('/opt/star23-staging-cd/bin/kubectl').toPath() : new File(ROOT, relative).toPath()
    if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS) || Files.isSymbolicLink(path) ||
            Files.size(path) <= 0 || Files.size(path) > limit || Files.getOwner(path).name != 'root' ||
            Files.getPosixFilePermissions(path).any { it in [PosixFilePermission.GROUP_WRITE, PosixFilePermission.OTHERS_WRITE] }) {
        throw new IllegalStateException('Untrusted protected payload')
    }
    return path
}

try {
    Jenkins jenkins = Jenkins.get()
    if (jenkins.initLevel.compareTo(InitMilestone.JOB_CONFIG_ADAPTED) < 0) {
        throw new IllegalStateException('Jenkins configuration is not adapted yet')
    }
    for (String directory in [ROOT, '/opt/star23-staging-cd', '/opt/star23-staging-cd/bin']) {
        def path = new File(directory).toPath()
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS) || Files.isSymbolicLink(path) || Files.getOwner(path).name != 'root' ||
                Files.getPosixFilePermissions(path).any { it in [PosixFilePermission.GROUP_WRITE, PosixFilePermission.OTHERS_WRITE] }) {
            throw new IllegalStateException('Untrusted protected directory')
        }
    }
    List names = ['CoordinatorPolicy.groovy', 'coordinator-pipeline.groovy', 'install-coordinators.groovy',
                  'validate_upstream.py', 'deploy_release.py']
    Map paths = names.collectEntries { name -> [(name):protectedPath(name, 512L * 1024)] }
    def kubectl = protectedPath('kubectl', 128L * 1024 * 1024)
    if (!Files.isExecutable(kubectl)) throw new IllegalStateException('kubectl is not executable')
    String template = new String(Files.readAllBytes(paths['coordinator-pipeline.groovy']), 'UTF-8')
    if (template.count('/* COORDINATOR_POLICY */') != 1) throw new IllegalStateException('Invalid pipeline template')
    String script = template.replace('/* COORDINATOR_POLICY */', new String(Files.readAllBytes(paths['CoordinatorPolicy.groovy']), 'UTF-8'))
    scriptHash = sha256(script.getBytes('UTF-8'))
    state = [schema_version:1, reviewed_script_sha256:scriptHash, status:'pending',
             payload_sha256:names.collectEntries { name -> [(name):sha256(Files.readAllBytes(paths[name]))] },
             automatic_build_scheduling:false]
    phase = 'required-plugins'
    List requiredPlugins = ['workflow-job', 'workflow-cps', 'workflow-multibranch', 'workflow-basic-steps',
                            'pipeline-model-definition', 'pipeline-stage-step', 'pipeline-build-step',
                            'credentials-binding', 'git', 'github-branch-source', 'cloudbees-folder',
                            'branch-api', 'scm-api', 'script-security']
    state.required_plugins = requiredPlugins.collectEntries { String name ->
        def plugin = jenkins.pluginManager.getPlugin(name)
        [(name):[installed:plugin != null, active:plugin?.isActive() == true, version:plugin?.version]]
    }
    List missingPlugins = requiredPlugins.findAll { name -> !state.required_plugins[name].active }
    if (!missingPlugins.isEmpty()) {
        throw new IllegalStateException('Required Jenkins plugins missing or inactive: ' + missingPlugins.join(', '))
    }
    // Revalidate/reapply every time: changed properties/flags must never be hidden by an old success marker.
    phase = 'groovy-classpath-parse'
    GroovyClassLoader parser = new GroovyClassLoader(jenkins.pluginManager.uberClassLoader)
    try { parser.parseClass(script, 'ReviewedStar23DirectCoordinator.groovy') } finally { parser.close() }
    phase = 'declarative-model-validation'
    if (Converter.scriptToPipelineDef(script) == null) throw new IllegalStateException('No declarative pipeline model')
    state.validation = [groovy_parse:true, declarative:true]
    phase = 'exact-script-approval'
    ScriptApproval approval = ScriptApproval.get()
    approval.preapprove(script, GroovyLanguage.get())
    approval.save()
    if (!approval.isScriptApproved(script, GroovyLanguage.get())) throw new IllegalStateException('Exact script approval failed')
    state.approval = [exact_script:true, language_class:GroovyLanguage.class.name, globally_approved_signatures:false]
    phase = 'installation'
    if (jenkins.queue.items.length != 0 || jenkins.getAllItems(WorkflowJob.class).any { it.isBuilding() }) throw new IllegalStateException('An existing Pipeline is running')
    String installer = new String(Files.readAllBytes(paths['install-coordinators.groovy']), 'UTF-8')
    if (installer.count('final boolean APPLY = false') != 1) throw new IllegalStateException('Unexpected installer apply guard')
    installer = installer.replace('final boolean APPLY = false', 'final boolean APPLY = true')
    new GroovyShell(jenkins.pluginManager.uberClassLoader, new Binding()).evaluate(installer, 'ReviewedDirectInstaller.groovy')
    phase = 'installation-verification'
    Map fixedJobs = ['cd/backend-dev':'ci/backend/dev', 'cd/ai-dev':'ci/ai/dev',
                     'cd/backend-main':'ci/backend/main', 'cd/ai-main':'ci/ai/main']
    fixedJobs.each { String name, String upstream ->
        WorkflowJob job = jenkins.getItemByFullName(name, WorkflowJob.class)
        verifyInstalledCoordinator(job, script, upstream)
    }
    if (!ScriptApproval.get().isScriptApproved(script, GroovyLanguage.get())) throw new IllegalStateException('Exact approval was revoked')
    state.status = 'succeeded'
    state.installation = [verified:true, enabled_buildable:true, absolute_success_triggers:true, non_aborting_concurrency:true]
    state.automatic_build_scheduling = false
    save(state)
    logger.info('Direct CD bootstrap installed/verified exact script SHA-256 ' + scriptHash + '; no builds scheduled')
} catch (Throwable error) {
    state.status = 'failed'
    state.failed_phase = phase
    state.error_type = error.class.name
    // Validation operates on reviewed static source, never credential bindings.
    state.error_message = error.message?.take(8000)
    state.reviewed_script_sha256 = scriptHash
    try { save(state) } catch (Throwable ignored) { }
    logger.warning('Direct CD bootstrap failed; phase=' + phase + '; reviewed SHA-256 ' + scriptHash + '; type=' + error.class.name)
}
