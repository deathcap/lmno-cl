
fs = require 'fs'
path = require 'path'
git = require 'git-node'

root = '../voxpopuli'
remoteRepoGroup = 'deathcap'

main = () ->
  readPackageJson()
  return

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

  theEnd = linkedPaths.slice(-1)[0]
  commitLogs = {}
  for file in linkedPaths
    projectName = path.basename(file)

    readRepo commitLogs, projectName, file, theEnd, (commitLogs) ->
      console.log commitLogs


readPackageJson = () ->
  packageJson = JSON.parse fs.readFileSync(path.join(root, 'package.json'))
  for depName, depVer of packageJson.dependencies
    isGit = depVer.indexOf('git://') == 0
    continue if !isGit

    isSpecific = depVer.indexOf('#') != -1
    continue if !isSpecific     # must be in git://foo#ref format. temporally consistent!

    [repoPath, commitRef] = depVer.split('#')

    console.log depName,repoPath,commitRef


readRepo = (commitLogs, projectName, gitPath, theEnd, callback) ->
  repo = git.repo path.join(gitPath, '.git')

  # see https://github.com/creationix/git-node/blob/master/examples/walk.js
  repo.logWalk 'HEAD', (err, log) ->
    throw err if err

    onRead = (err, commit) ->
      throw err if err
      if !commit
        # end of commits for this project
        if gitPath == theEnd
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
  commitLogs[projectName] ?= []

  firstLine = (s) ->
    s.split('\n')[0]

  message = "#{remoteRepoGroup}/#{projectName}@#{commit.hash} #{firstLine commit.message}"
  commitLogs[projectName].push(message)


main()

