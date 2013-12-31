
fs = require 'fs'
path = require 'path'
git = require 'git'

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
  
  repo = new git.Git(p3)
  console.log p3, repo

  repo.rev_list {}, 'master', (err, result) ->
    console.log err,result
