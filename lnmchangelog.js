// Generated by CoffeeScript 1.6.3
(function() {
  var firstLine, fs, git, logCommit, main, path, readRepo, remoteRepoGroup, root;

  fs = require('fs');

  path = require('path');

  git = require('git-node');

  root = '../voxpopuli';

  remoteRepoGroup = 'deathcap';

  main = function() {
    var file, linkedPaths, node_modules, p1, p2, p3, projectName, stats, theEnd, _i, _j, _len, _len1, _ref, _results;
    node_modules = path.join(root, 'node_modules');
    linkedPaths = [];
    _ref = fs.readdirSync(node_modules);
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      file = _ref[_i];
      p1 = path.join(node_modules, file);
      stats = fs.lstatSync(p1);
      if (!stats.isSymbolicLink()) {
        continue;
      }
      p2 = fs.readlinkSync(p1);
      p3 = fs.readlinkSync(p2);
      linkedPaths.push(p3);
    }
    theEnd = linkedPaths[0];
    _results = [];
    for (_j = 0, _len1 = linkedPaths.length; _j < _len1; _j++) {
      file = linkedPaths[_j];
      projectName = path.basename(file);
      readRepo(projectName, file, theEnd, function(collectedCommitLogs) {
        return console.log(collectedCommitLogs);
      });
      break;
    }
    return _results;
  };

  readRepo = function(projectName, gitPath, theEnd, callback) {
    var collectedCommitLogs, repo;
    repo = git.repo(path.join(gitPath, '.git'));
    collectedCommitLogs = {};
    return repo.logWalk('HEAD', function(err, log) {
      var onRead;
      if (err) {
        throw err;
      }
      onRead = function(err, commit) {
        if (err) {
          throw err;
        }
        if (!commit) {
          if (gitPath === theEnd) {
            callback(collectedCommitLogs);
          }
          return;
        }
        logCommit(collectedCommitLogs, projectName, commit);
        return repo.treeWalk(commit.tree, function(err, tree) {
          var onEntry;
          if (err) {
            throw err;
          }
          onEntry = function(err, entry) {
            if (err) {
              throw err;
            }
            if (!entry) {
              return log.read(onRead);
            }
            return tree.read(onEntry);
          };
          return tree.read(onEntry);
        });
      };
      return log.read(onRead);
    });
  };

  logCommit = function(collectedCommitLogs, projectName, commit) {
    var message;
    if (collectedCommitLogs[projectName] == null) {
      collectedCommitLogs[projectName] = [];
    }
    message = "" + remoteRepoGroup + "/" + projectName + "@" + commit.hash + " " + (firstLine(commit.message));
    return collectedCommitLogs[projectName].push(message);
  };

  firstLine = function(s) {
    return s.split('\n')[0];
  };

  main();

}).call(this);
