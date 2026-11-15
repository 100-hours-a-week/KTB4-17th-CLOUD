// Jenkins Script Console only. Preview is the default; no jobs are scheduled.
// After reviewing the preview, an administrator may change APPLY to true.
import com.cloudbees.hudson.plugins.folder.Folder
import hudson.model.Result
import hudson.slaves.EnvironmentVariablesNodeProperty
import groovy.xml.MarkupBuilder
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.attribute.PosixFilePermission
import java.security.MessageDigest
import jenkins.model.Jenkins
import jenkins.triggers.ReverseBuildTrigger
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.job.properties.DisableConcurrentBuildsJobProperty
import org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty

// Job.addProperty appends; explicitly remove every old instance, including any
// duplicates left by an earlier installer. Other JobProperties remain intact.
void replaceCoordinatorProperties(WorkflowJob job, String upstream) {
    def oldTriggers
    while ((oldTriggers = job.getProperty(PipelineTriggersJobProperty.class)) != null) {
        oldTriggers.stopTriggers()
        job.removeProperty(oldTriggers)
    }
    def oldConcurrency
    while ((oldConcurrency = job.getProperty(DisableConcurrentBuildsJobProperty.class)) != null) {
        job.removeProperty(oldConcurrency)
    }
    job.addProperty(new DisableConcurrentBuildsJobProperty())
    ReverseBuildTrigger trigger = new ReverseBuildTrigger('/' + upstream)
    trigger.setThreshold(Result.SUCCESS)
    // WorkflowJob.addProperty starts the new trigger property itself.
    job.addProperty(new PipelineTriggersJobProperty([trigger]))
}

// Upgrade only jobs whose first description line is a known managed marker.
boolean managedCoordinator(String name, String description) {
    if (!(name in ['cd/backend-dev', 'cd/ai-dev', 'cd/backend-main', 'cd/ai-main'])) return false
    String first = description?.readLines()?.find { true }
    return first == 'Managed: star23-source-free-direct-coordinator-v2' ||
            (name in ['cd/backend-dev', 'cd/ai-dev'] && first == 'Managed: star23-source-free-staging-coordinator-v1')
}

/** Jenkins persists this complete initial XML atomically, including ownership.
 * A crash before later property installation therefore leaves a managed job
 * that can be recognized and repaired on reapply, never an unmarked orphan.
 */
WorkflowJob createManagedCoordinator(Folder folder, String shortName, String descriptionText, String scriptText) {
    StringWriter buffer = new StringWriter()
    MarkupBuilder xml = new MarkupBuilder(buffer)
    xml.'flow-definition' {
        description(descriptionText)
        keepDependencies(false)
        properties()
        definition(class:'org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition') {
            script(scriptText)
            sandbox(false)
        }
        disabled(false)
    }
    return (WorkflowJob) folder.createProjectFromXML(shortName,
            new ByteArrayInputStream(buffer.toString().getBytes('UTF-8')))
}

final boolean APPLY = false
final String ROOT = '/opt/star23-direct-cd'
final String MARKER = 'Managed: star23-source-free-direct-coordinator-v2'
final List<String> files = ['CoordinatorPolicy.groovy', 'coordinator-pipeline.groovy',
                            'validate_upstream.py', 'deploy_release.py']

def protectedPath = { String name, long limit = 512 * 1024 ->
    def path = new File(ROOT, name).toPath()
    if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS) || Files.isSymbolicLink(path) ||
            Files.size(path) <= 0 || Files.size(path) > limit || Files.getOwner(path).name != 'root') {
        throw new IllegalStateException('Protected controller payload is missing or not root-owned: ' + name)
    }
    Set modes = Files.getPosixFilePermissions(path)
    if (modes.contains(PosixFilePermission.GROUP_WRITE) || modes.contains(PosixFilePermission.OTHERS_WRITE)) {
        throw new IllegalStateException('Protected controller payload is writable by an untrusted account: ' + name)
    }
    return path
}
def rootPath = new File(ROOT).toPath()
if (!Files.isDirectory(rootPath, LinkOption.NOFOLLOW_LINKS) || Files.isSymbolicLink(rootPath) ||
        Files.getOwner(rootPath).name != 'root' ||
        Files.getPosixFilePermissions(rootPath).any { it in [PosixFilePermission.GROUP_WRITE, PosixFilePermission.OTHERS_WRITE] }) {
    throw new IllegalStateException('The protected helper directory must be a root-owned non-writable directory')
}
Map paths = files.collectEntries { String name -> [(name):protectedPath(name)] }
def historicalRoot = new File('/opt/star23-staging-cd').toPath()
if (!Files.isDirectory(historicalRoot, LinkOption.NOFOLLOW_LINKS) || Files.isSymbolicLink(historicalRoot) ||
        Files.getOwner(historicalRoot).name != 'root' ||
        Files.getPosixFilePermissions(historicalRoot).any { it in [PosixFilePermission.GROUP_WRITE, PosixFilePermission.OTHERS_WRITE] }) {
    throw new IllegalStateException('The fixed existing kubectl root is not protected')
}
def binaryDirectory = new File('/opt/star23-staging-cd/bin').toPath()
if (!Files.isDirectory(binaryDirectory, LinkOption.NOFOLLOW_LINKS) || Files.isSymbolicLink(binaryDirectory) ||
        Files.getOwner(binaryDirectory).name != 'root' ||
        Files.getPosixFilePermissions(binaryDirectory).any { it in [PosixFilePermission.GROUP_WRITE, PosixFilePermission.OTHERS_WRITE] }) {
    throw new IllegalStateException('The protected kubectl directory must be root-owned and non-writable')
}
def kubectlPath = binaryDirectory.resolve('kubectl')
if (!Files.isRegularFile(kubectlPath, LinkOption.NOFOLLOW_LINKS) || Files.isSymbolicLink(kubectlPath) ||
        Files.size(kubectlPath) <= 0 || Files.size(kubectlPath) > 128L * 1024 * 1024 ||
        Files.getOwner(kubectlPath).name != 'root' ||
        Files.getPosixFilePermissions(kubectlPath).any { it in [PosixFilePermission.GROUP_WRITE, PosixFilePermission.OTHERS_WRITE] }) {
    throw new IllegalStateException('The fixed existing kubectl is not protected')
}
if (!Files.isExecutable(kubectlPath)) throw new IllegalStateException('Protected kubectl must be executable')
String policyText = new String(Files.readAllBytes(paths['CoordinatorPolicy.groovy']), 'UTF-8')
String template = new String(Files.readAllBytes(paths['coordinator-pipeline.groovy']), 'UTF-8')
String placeholder = '/* COORDINATOR_POLICY */'
if (template.count(placeholder) != 1) throw new IllegalStateException('Expected one policy insertion point')
String script = template.replace(placeholder, policyText)
String scriptSha = MessageDigest.getInstance('SHA-256').digest(script.getBytes('UTF-8')).encodeHex().toString()

Jenkins jenkins = Jenkins.get()
for (String plugin in ['workflow-job', 'workflow-cps', 'pipeline-model-definition', 'pipeline-build-step',
                      'credentials-binding', 'git', 'github-branch-source', 'cloudbees-folder']) {
    if (!jenkins.pluginManager.getPlugin(plugin)?.isActive()) throw new IllegalStateException('Required Jenkins plugin is missing: ' + plugin)
}
Map flags = [:]
jenkins.globalNodeProperties.findAll { it instanceof EnvironmentVariablesNodeProperty }.each { property ->
    ['STAR23_AUTO_DEPLOY_STAGING', 'AI_STAGING_AUTO_DEPLOY_ENABLED',
     'STAR23_AUTO_DEPLOY_PROD', 'AI_PROD_AUTO_DEPLOY_ENABLED'].each { name ->
        if (property.envVars.containsKey(name)) {
            if (flags.containsKey(name)) throw new IllegalStateException('Duplicate global deployment flag')
            flags[name] = property.envVars[name]
        }
    }
}
for (String name in ['STAR23_AUTO_DEPLOY_STAGING', 'AI_STAGING_AUTO_DEPLOY_ENABLED',
                      'STAR23_AUTO_DEPLOY_PROD', 'AI_PROD_AUTO_DEPLOY_ENABLED']) {
    if (!(flags[name]?.trim()?.toLowerCase(Locale.ROOT) in [null, '', 'false'])) {
        throw new IllegalStateException('All legacy deployment flags must remain false: ' + name)
    }
}
// All legacy global deployment paths must remain disabled; the installer never changes flags.
println groovy.json.JsonOutput.toJson([mode:APPLY ? 'apply' : 'preview', script_sha256:scriptSha,
        original_flags:flags, helper_sha256:files.collectEntries { name ->
            [(name):MessageDigest.getInstance('SHA-256').digest(Files.readAllBytes(paths[name])).encodeHex().toString()]
        }])

Map<String,String> jobs = ['cd/backend-dev':'ci/backend/dev', 'cd/ai-dev':'ci/ai/dev',
                           'cd/backend-main':'ci/backend/main', 'cd/ai-main':'ci/ai/main']
def folder = jenkins.getItemByFullName('cd')
if (folder != null && !(folder instanceof Folder)) throw new IllegalStateException('Existing cd item is not a Folder')
jobs.each { String name, String upstream ->
    if (!(jenkins.getItemByFullName(upstream) instanceof WorkflowJob)) throw new IllegalStateException('Fixed upstream job is missing')
    def existing = jenkins.getItemByFullName(name)
    if (existing != null && (!(existing instanceof WorkflowJob) || !managedCoordinator(name, existing.description))) {
        throw new IllegalStateException('Refusing to replace an unrelated Jenkins job: ' + name)
    }
    if (existing?.isBuilding() || jenkins.queue.items.any { it.task == existing && existing != null }) throw new IllegalStateException('Wait for the existing coordinator to finish before updating it')
    println groovy.json.JsonOutput.toJson([job:name, upstream:upstream, threshold:'SUCCESS',
            definition:'trusted inline, no SCM checkout', exists:existing != null])
}

if (APPLY) {
    if (folder == null) folder = jenkins.createProject(Folder.class, 'cd')
    jobs.each { String name, String upstream ->
        WorkflowJob job = jenkins.getItemByFullName(name, WorkflowJob.class)
        String description = MARKER + '\nFixed dev/staging or main/prod profile. Source repository files are never changed. Definition SHA-256: ' + scriptSha
        if (job == null) job = createManagedCoordinator(folder, name.substring(3), description, script)
        job.setDefinition(new CpsFlowDefinition(script, false))
        job.setDescription(description)
        replaceCoordinatorProperties(job, upstream)
        job.save()
    }
    jenkins.rebuildDependencyGraphAsync()
    println 'Installed the four coordinator jobs. No build was scheduled; source jobs and legacy flags were unchanged.'
} else {
    println 'Preview only. No Jenkins job, trigger, flag, credential, repository or cluster was changed.'
}
