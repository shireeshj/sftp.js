# sftp library for node

## Readme driven development

```javascript

var sftp = new SFTP({
  host: 'blahblah.com'
, port: 22
, user: 'action'
, key: 'path/to/private.key'
});

sftp.connect(function(err) {
  // once sftp is connected this callback is invoked
});

sftp.bye(function (err) {
  // ends sftp connection and kills pty
});

sftp.ls('path/to/heaven', function(err, list:Array) {
  /* list:
     [ { n: 'foo', d: false },  // n: name,  d: directory
       { n: 'bar', d: true },
       { n: 'baz', d: false }
       { n: 'qux', d: false } ]
  */
});

sftp.put('path/to/new/file', 'file content':Buffer|String, function(err) {});
sftp.get('path/to/file', function(err, content:Buffer) {
  var contentString = content.toString('utf8');
});

sftp.rm('path/to/file', function(err) {});
sftp.rmdir('path/to/dir', function(err) {});

sftp.mkdir('path/to/new/dir', function(err) {});
sftp.on('close', function(err) {});

// to be implemented later:

sftp.chmod('0755', 'path/to/heaven', function(err) {});
sftp.chown('user', 'path/to/heaven', function(err) {});
sftp.chgrp('group', 'path/to/heaven', function(err) {});
sftp.df('user', 'path/to/heaven', function (err, info:Object) {
  // info: { size: 12345678, used: 1234567, avail: 11111111 }
});
sftp.ln('path/to/file', 'path/to/link', function(err) {});
```

