
fs = require 'fs'
path = require 'path'
git = require 'git-node'

root = '../voxpopuli'

node_modules = path.join(root, 'node_modules')

files = fs.readdirSync(node_modules)
console.log files
for file in files
  p1 = path.join(node_modules, file)    # project link
  stats = fs.lstatSync(p1)
  if not stats.isSymbolicLink()
    continue

  p2 = fs.readlinkSync(p1)              # /usr/local/lib/node_modules link
  p3 = fs.readlinkSync(p2)              # final destination link
 
  project = p3
  repo = git.repo path.join(p3, '.git')
  console.log p3, repo

  # based off https://github.com/creationix/git-node/blob/master/examples/walk.js
  repo.logWalk 'HEAD', (err, log) ->
    throw err if err

    onRead = (err, commit) ->
      throw err if err
      return if !commit
      logCommit(project, commit)
      repo.treeWalk commit.tree, (err, tree) ->
        throw err if err
        onEntry = (err, entry) ->
          throw err if err
          return log.read(onRead) if !entry
          return tree.read(onEntry)

        tree.read(onEntry)

    return log.read onRead

  break

logCommit = (project, commit) ->
  console.log "#{project}@#{commit.hash} #{commit.author.name} #{firstLine commit.message}"

firstLine = (s) ->
  s.split('\n')[0]
