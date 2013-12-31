// Generated by CoffeeScript 1.6.3
(function() {
  var exec, file, files, fs, node_modules, p1, p2, p3, path, root, stats, _i, _len;

  fs = require('fs');

  path = require('path');

  exec = require('exec');

  root = '../voxpopuli';

  node_modules = path.join(root, 'node_modules');

  files = fs.readdirSync(node_modules);

  console.log(files);

  for (_i = 0, _len = files.length; _i < _len; _i++) {
    file = files[_i];
    p1 = path.join(node_modules, file);
    stats = fs.lstatSync(p1);
    if (!stats.isSymbolicLink()) {
      continue;
    }
    p2 = fs.readlinkSync(p1);
    p3 = fs.readlinkSync(p2);
    console.log(p3);
    exec(['ls', '-l', p3], function(err, out, code) {
      if (err) {
        throw err;
      }
      console.log(out);
      return console.log(code);
    });
  }

}).call(this);
