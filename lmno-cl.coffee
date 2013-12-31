
fs = require 'fs'
path = require 'path'
git = require 'git-node'

root = '../voxpopuli'

main = () ->
  rawPackageJson = fs.readFileSync(path.join(root, 'package.json'))

  packageJson = JSON.parse rawPackageJson
  depVers = getDepVers(packageJson)
  [mostCommonHost, mostCommonGroup] = getCommonHostGroup(depVers)
  if mostCommonHost != 'github.com'
    print "warning: unknown git host #{mostCommonHost}, commit references may be incorrect"

  cutCommits = getPackageJsonCommits(mostCommonHost, mostCommonGroup, depVers)

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
  console.log 'numProjects',numProjects
  console.log 'linkedPaths',linkedPaths
  commitLogs = {}
  newestCommits = {}
  for file in linkedPaths
    projectName = path.basename(file)

    cutCommit = cutCommits[projectName]
    if !cutCommit?
      throw "node module #{projectName} linked but not found in package.json!"

    readRepo commitLogs, newestCommits, cutCommit, projectName, file, numProjects, (commitLogs) ->
      console.log "======="
      console.log commitLogs
      console.log "======="
      console.log newestCommits
      updatePackageJson(cutCommits, rawPackageJson.toString(), commitLogs, newestCommits)

      logRepoGroup = mostCommonGroup # TODO: get from 'git remote -v' instead?
      msg = addCommitLog(logRepoGroup, commitLogs)
      console.log "log=",msg

updatePackageJson = (cutCommits, rawPackageJson, commitLogs, newestCommits) ->
  for projectName, newestCommit of newestCommits
    oldCommit = cutCommits[projectName]
    # replace the package.json file textually so it is modified in-place, not rewritten
    # hope there is not the same commit hash shared between multiple projects
    rawPackageJson = rawPackageJson.replace(oldCommit, newestCommit)

  console.log rawPackageJson


addCommitLog = (logRepoGroup, commitLogs) ->
  detail = ''
  projectsUpdated = []

  firstLine = (s) ->
    s.split('\n')[0]

  for projectName, logs of commitLogs
    continue if logs.length == 0  # skip if nothing changed
    projectsUpdated.push(projectName)

    for [projectName, commit] in logs
      messageLine = "#{logRepoGroup}/#{projectName}@#{commit.hash} #{firstLine commit.message}"
      detail += messageLine + '\n'

  oneliner = 'Update ' + projectsUpdated.join(', ')
  return oneliner + '\n\n' + detail

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

  for depName, depVer of depVers
    [repoURL, commitRef] = depVer.split('#')
    ourPrefix = "git://#{expectedHost}/#{expectedGroup}/"  # assume most frequently specified host and group is ours; ignore others
    isOurRepo = repoURL.indexOf(ourPrefix) == 0
    continue if !isOurRepo

    projectName = repoURL.split('/')[4]
    projectName = projectName.replace('.git', '')  # optional, but probably a good idea

    if depName != projectName
      throw "unexpected package.json entry: dependency name #{depName} != project name #{projectName} in #{depVer}, why?"

    usedCommits[projectName] = commitRef

  return usedCommits


readRepo = (commitLogs, newestCommits, cutCommit, projectName, gitPath, numProjects, callback) ->
  repo = git.repo path.join(gitPath, '.git')

  commitLogs[projectName] = []

  # see https://github.com/creationix/git-node/blob/master/examples/walk.js
  repo.logWalk 'HEAD', (err, log) ->
    throw err if err

    onRead = (err, commit) ->
      throw err if err

      if commit
        newestCommits[projectName] ?= commit.hash

      if !commit or commit.hash == cutCommit
        # end of commits for this project
        
        # last project, commit logs all completed, so can continue processing
        if Object.keys(commitLogs).length == numProjects
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


main()

