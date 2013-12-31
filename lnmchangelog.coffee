
fs = require 'fs'
path = require 'path'
git = require 'git-node'

root = '../voxpopuli'
remoteRepoGroup = 'deathcap'

main = () ->
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

  #theEnd = linkedPaths.slice(-1)[0]
  theEnd = linkedPaths[0]
  for file in linkedPaths
    projectName = path.basename(file)

    readRepo projectName, file, theEnd, (collectedCommitLogs) ->
      console.log collectedCommitLogs

    break

readRepo = (projectName, gitPath, theEnd, callback) ->
  repo = git.repo path.join(gitPath, '.git')

  collectedCommitLogs = {}

  # see https://github.com/creationix/git-node/blob/master/examples/walk.js
  repo.logWalk 'HEAD', (err, log) ->
    throw err if err

    onRead = (err, commit) ->
      throw err if err
      if !commit
        # end of commits for this project
        if gitPath == theEnd
          callback(collectedCommitLogs)
        return
      logCommit(collectedCommitLogs, projectName, commit)
      repo.treeWalk commit.tree, (err, tree) ->
        throw err if err
        onEntry = (err, entry) ->
          throw err if err
          return log.read(onRead) if !entry
          return tree.read(onEntry)

        tree.read(onEntry)

    return log.read onRead


logCommit = (collectedCommitLogs, projectName, commit) ->
  collectedCommitLogs[projectName] ?= []

  message = "#{remoteRepoGroup}/#{projectName}@#{commit.hash} #{firstLine commit.message}"
  collectedCommitLogs[projectName].push(message)

firstLine = (s) ->
  s.split('\n')[0]

main()

