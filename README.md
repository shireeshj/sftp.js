# sftp library for node

## Readme driven development

```javascript

var sftp = new SFTP({
  host: 'blahblah.com'
, port: 22
, user: 'action'
, key: '-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED...'
});

sftp.connect(function(err) {
  // once sftp is connected this callback is invoked
});

sftp.destroy(function (err) {
  // ends sftp connection and kills pty
});

sftp.ls('path/to/heaven', function(err, list:Array) {
  /* list:
     [
       [ 'foo', false, 1024 ]  // [ name, isDirectory, fileSize ]
     , [ 'bar', true,  4096 ]
     , [ 'baz', false, 123 ]
     , [ 'qux', false, 456 ]
     ]
  */
});

sftp.put('path/to/new/file', 'file content':Buffer|String, function(err) {});

sftp.get('path/to/file', function(err, content:Buffer, fileType:String) {
  var contentString = content.toString('utf8');
});

sftp.rm('path/to/file', function(err) {});
sftp.rmdir('path/to/dir', function(err) {});

sftp.mkdir('path/to/new/dir', function(err) {});

// to be implemented later:

sftp.on('connection', function(err, sftp) {});
sftp.on('close', function(err, sftp) {});

sftp.chmod('0755', 'path/to/heaven', function(err) {});
sftp.chown('user', 'path/to/heaven', function(err) {});
sftp.chgrp('group', 'path/to/heaven', function(err) {});
sftp.df('user', 'path/to/heaven', function (err, info:Object) {
  // info: { size: 12345678, used: 1234567, avail: 11111111 }
});
sftp.ln('path/to/file', 'path/to/link', function(err) {});
```
