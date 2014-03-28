
fs = require 'fs'
path = require 'path'
git = require 'git-node'
util = require 'util'

root = '.'

dryRun = '-n' in process.argv       # don't update package.json
logVerbose = '-v' in process.argv   # log new package.json to console

tagline = 'Commit message generated by https://github.com/deathcap/lmno-cl'

main = () ->
  rawPackageJson = fs.readFileSync(path.join(root, 'package.json'))

  packageJson = JSON.parse rawPackageJson
  depVers = getDepVers(packageJson)
  [mostCommonHost, mostCommonGroup] = getCommonHostGroup(depVers)
  if mostCommonHost != 'github.com'
    console.log packageJson
    console.log "\nNo github.com URL dependencies found!"

  [cutCommits, projectName2DepName] = getPackageJsonCommits(mostCommonHost, mostCommonGroup, depVers)

  node_modules = path.join(root, 'node_modules')
  linkedPaths = []

  # find 'npm link' modules
  for file in fs.readdirSync(node_modules)
    p1 = path.join(node_modules, file)    # project link
    stats = fs.lstatSync(p1)
    if not stats.isSymbolicLink()
      continue

    p2 = fs.readlinkSync(p1)              # /usr/local/lib/node_modules link
    p3 = fs.readlinkSync(p2)              # final destination link

    linkedPaths.push(p3)

  numProjects = linkedPaths.length
  #console.log 'numProjects',numProjects
  #console.log 'linkedPaths',linkedPaths
  commitLogs = {}
  newestCommits = {}
  depIsIgnored = {}

  # for file, fileNum in linkedPaths
  readProject = (fileNum) ->
    file = linkedPaths[fileNum]
    projectName = path.basename(file)

    depName = projectName2DepName[projectName]
    depName ?= projectName  # if not linked

    process.stderr.write 'found '+depName+'\n'

    cutCommit = cutCommits[depName]
    if !cutCommit?
      process.stderr.write "# WARNING: node module #{projectName} linked but not found in package.json! (ignoring)\n"
      #continue   # can't, because isLast depends on order
      depIsIgnored[depName] = true

    isLast = fileNum == linkedPaths.length - 1

    readRepo commitLogs, newestCommits, cutCommit, projectName, file, (commitLogs) ->
      if not isLast
        return readProject(fileNum + 1)

      #console.log "======="
      #console.log commitLogs
      #console.log "======="
      #console.log newestCommits
      updatePackageJson(cutCommits, projectName2DepName, depIsIgnored, rawPackageJson.toString(), commitLogs, newestCommits)

      logRepoGroup = mostCommonGroup # TODO: get from 'git remote -v' instead?
      msg = addCommitLog(logRepoGroup, commitLogs, projectName2DepName, depIsIgnored)

      # run this through: git commit package.json -F -
      cmd = ['git', 'commit', 'package.json', '-m', msg]
      escaped = shellescape(cmd)
      console.log escaped
      if logVerbose
        process.stderr.write escaped + '\n'

  readProject(0)

updatePackageJson = (cutCommits, projectName2DepName, depIsIgnored, rawPackageJson, commitLogs, newestCommits) ->
  for projectName, newestCommit of newestCommits
    depName = projectName2DepName[projectName]
    depName ?= projectName

    oldCommit = cutCommits[depName]
    # replace the package.json file textually so it is modified in-place, not rewritten
    # hope there is not the same commit hash shared between multiple projects
    rawPackageJson = rawPackageJson.replace(oldCommit, newestCommit) unless depIsIgnored[depName]

  if logVerbose
    process.stderr.write rawPackageJson + '\n'
  if not dryRun
    fs.writeFileSync 'package.json', rawPackageJson


addCommitLog = (logRepoGroup, commitLogs, projectName2DepName, depIsIgnored) ->
  detail = ''
  projectsUpdated = []

  firstLine = (s) ->
    s.split('\n')[0]

  for projectName, logs of commitLogs
    continue if logs.length == 0  # skip if nothing changed
    depName = projectName2DepName[projectName]
    depName ?= projectName
    continue if depIsIgnored[depName]

    projectsUpdated.push(projectName)

    for [projectName, commit] in logs
      commitMessage = commit.message.replace /GH-(\d+)/g, "#{logRepoGroup}/#{projectName}#$1"

      messageLine = "#{logRepoGroup}/#{projectName}@#{commit.hash} #{firstLine commitMessage}"
      detail += messageLine + '\n'

  oneliner = 'Update ' + projectsUpdated.join(', ')
  return oneliner + '\n\n' + detail + '\n' + tagline

getDepVers = (packageJson) ->
  depVers = {}
  for depName, depVer of packageJson.dependencies
    isGit = depVer.indexOf('git://') == 0
    continue if !isGit

    isSpecific = depVer.indexOf('#') != -1
    continue if !isSpecific     # must be in git://foo#ref format. temporally consistent!

    depVers[depName] = depVer
  return depVers

getCommonHostGroup = (depVers) ->
  repoHostFreq = {}
  repoGroupFreq = {}
  for depName, depVer of depVers
    [ignoredProtocol, ignoredBlank, repoHost, repoGroup, repoPath] = depVer.split('/')
   
    repoHostFreq[repoHost] ?= 0
    repoHostFreq[repoHost] += 1

    repoGroupFreq[repoGroup] ?= 0
    repoGroupFreq[repoGroup] += 1

  host = mostCommon repoHostFreq
  group = mostCommon repoGroupFreq

  [host, group]

mostCommon = (obj) ->
  maxFreq = 0
  ret = undefined
  for name, freq of obj
    if freq > maxFreq
      ret = name
  return ret


getPackageJsonCommits = (expectedHost, expectedGroup, depVers) ->
  usedCommits = {}
  projectName2DepName = {}

  for depName, depVer of depVers
    [repoURL, commitRef] = depVer.split('#')
    ourPrefix = "git://#{expectedHost}/#{expectedGroup}/"  # assume most frequently specified host and group is ours; ignore others
    isOurRepo = repoURL.indexOf(ourPrefix) == 0
    continue if !isOurRepo

    projectName = repoURL.split('/')[4]
    projectName = projectName.replace('.git', '')  # optional, but probably a good idea

    if depName != projectName
      process.stderr.write "# WARNING: unexpected package.json entry: dependency name #{depName} != project name #{projectName} in #{depVer}, why? (using dependency name #{depName}n"
      projectName2DepName[projectName] = depName

    usedCommits[depName] = commitRef

  return [usedCommits, projectName2DepName]


readRepo = (commitLogs, newestCommits, cutCommit, projectName, gitPath, callback) ->
  repo = git.repo path.join(gitPath, '.git')

  commitLogs[projectName] = []
  # see https://github.com/creationix/git-node/blob/master/examples/walk.js
  repo.logWalk 'HEAD', (err, log) ->
    throw err if err

    shallow = false

    onRead = (err, commit) ->
      throw err if err

      if commit
        newestCommits[projectName] ?= commit.hash

      if !commit or commit.hash == cutCommit
        # end of commits for this project
        
        callback(commitLogs)
        return

      logCommit(commitLogs, projectName, commit)
      repo.treeWalk commit.tree, (err, tree) ->
        throw err if err
        onEntry = (err, entry) ->
          #throw err if err # ignore because of ENOENT voxel-engine/.git/objects/76/add878f8dd778c3381fb3da45c8140db7db510
          return log.read(onRead) if !entry
          return tree.read(onEntry)

        tree.read(onEntry)

    return log.read onRead


logCommit = (commitLogs, projectName, commit) ->
  commitLogs[projectName].push [projectName, commit]

# escaping code based on https://github.com/bahamas10/node-shell-escape

# dangerous characters to the shell,
# see http://mywiki.wooledge.org/BashGuide/SpecialCharacters
escapechars = [
  ' ', ';', '&', '#', '>', '<', '{', '}', '$', '(', 
  ')', '[', ']', '"', '|', '*', '!', '^', '?',
  '+', '~', '`'
]

# return a shell compatible format
shellescape = (a) ->
  ret = []

  a.forEach (s) ->
    # quote troublesome characters
    for i in escapechars
      if s.indexOf(escapechars[i]) > -1
        s = util.inspect(s)
        break

    # escaping ' doesn't work, replace with '"'"'
    s = s.replace(/'/g, '\'"\'"\'')

    needsQuoting = s.indexOf(' ') != -1 || s.indexOf('\n') != -1
    
    if needsQuoting
      s = "'#{s}'"

    ret.push(s)

  ret.join(' ')


main()

