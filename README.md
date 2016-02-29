# Patch to fix SSL verification in em-http patch

The Ubuntu team [recently released an update to the `ca-certificates`
package](https://launchpadlibrarian.net/242531582/ca-certificates_20141019ubuntu0.12.04.1_20160104ubuntu0.12.04.1.diff.gz)
that removes several root certificates, including one that is used to sign part
of the chain for `login.mailchimp.com`'s certificate(GTE CyberTrust Global Root).

If you run `strace` on `openssl s_client` you can see it attempting to find
Cybertrust's certificate in the trust store:

```console
$ openssl x509 -noout -in GTE_CyberTrust_Global_Root.crt -hash
c692a373

$ strace -eopen,stat openssl s_client -CApath /etc/ssl/certs -connect login.mailchimp.com:443
...
stat("/etc/ssl/certs/c692a373.0", 0x7fffd8693ac0) = -1 ENOENT (No such file or directory)
stat("/usr/lib/ssl/certs/c692a373.0", 0x7fffd8693ac0) = -1 ENOENT (No such file or directory)
stat("/etc/ssl/certs/653b494a.0", {st_mode=S_IFREG|0644, st_size=1261, ...}) = 0
open("/etc/ssl/certs/653b494a.0", O_RDONLY) = 4
stat("/etc/ssl/certs/653b494a.1", 0x7fffd8693ac0) = -1 ENOENT (No such file or directory)
open("/etc/localtime", O_RDONLY|O_CLOEXEC) = 4
depth=2 C = IE, O = Baltimore, OU = CyberTrust, CN = Baltimore CyberTrust Root
verify return:1
depth=1 C = NL, L = Amsterdam, O = Verizon Enterprise Solutions, OU = Cybertrust, CN = Verizon Akamai SureServer CA G14-SHA2
verify return:1
depth=0 C = US, ST = GA, L = Atlanta, O = ROCKET SCIENCE GROUP, OU = Product Development, CN = *.mailchimp.com
verify return:1
---
Certificate chain
 0 s:/C=US/ST=GA/L=Atlanta/O=ROCKET SCIENCE GROUP/OU=Product Development/CN=*.mailchimp.com
   i:/C=NL/L=Amsterdam/O=Verizon Enterprise Solutions/OU=Cybertrust/CN=Verizon Akamai SureServer CA G14-SHA2
 1 s:/C=NL/L=Amsterdam/O=Verizon Enterprise Solutions/OU=Cybertrust/CN=Verizon Akamai SureServer CA G14-SHA2
   i:/C=IE/O=Baltimore/OU=CyberTrust/CN=Baltimore CyberTrust Root
 2 s:/C=IE/O=Baltimore/OU=CyberTrust/CN=Baltimore CyberTrust Root
   i:/C=US/O=GTE Corporation/OU=GTE CyberTrust Solutions, Inc./CN=GTE CyberTrust Global Root
---
...
    Start Time: 1456769006
    Timeout   : 300 (sec)
    Verify return code: 0 (ok)
```

`openssl s_client` Is able to verify this certificate because the `Baltimore CyberTrust Root` certificate is
included in the ca-certificates bundle.


```console
$ sudo dpkg -c ca-certificates_20141019ubuntu0.12.04.1_all.deb
...
-rw-r--r-- root/root      1261 2015-02-20 13:51 ./usr/share/ca-certificates/mozilla/Baltimore_CyberTrust_Root.crt
...
```

Unfortunately the patched version of `em-http` that is distributed with faraday
requires all certificates in the chain to be trusted before it'll verify the
connection. This causes ssl verification for domains with untrusted
roots to fail. One noticeable example of this is MailChimp:

```console
$ bundle install

$ strace -f -e trace=open,stat ruby testcase.rb 2>&1 | grep -vE "gem|ruby|localtime|/home/|/etc/|/local/bin"
...
[pid 14454] open("/dev/urandom", O_RDONLY|O_NOCTTY|O_NONBLOCK) = 10
[pid 14454] open("/usr/lib/ssl/cert.pem", O_RDONLY) = -1 ENOENT (No such file or directory)
[pid 14454] stat("/usr/lib/ssl/certs/c692a373.0", 0x7fff974c8ff0) = -1 ENOENT (No such file or directory)
/home/vagrant/development/mailchimp-test/broken-monkey-patch.rb:21:in `ssl_verify_peer': unable to verify the server certificate for "login.mailchimp.com" (OpenSSL::SSL::SSLError)
	from /home/vagrant/development/mailchimp-test/vendor/ruby/2.1.0/gems/eventmachine-le-1.1.7/lib/eventmachine.rb:173:in `run_machine'
	from /home/vagrant/development/mailchimp-test/vendor/ruby/2.1.0/gems/eventmachine-le-1.1.7/lib/eventmachine.rb:173:in `run'
	from testcase.rb:14:in `<main>'
```

The workaround appears to be to remove the "unable to verify server certificate"
error from the patch and instead delay verification of mailchimp's certificate
until the handshake is complete:

```console
$ strace -f -e trace=open,stat ruby testcase.rb 2>&1 | grep -vE "gem|ruby|localtime|/home/|/etc/|/local/bin"
...
[pid 15752] open("/usr/lib/ssl/cert.pem", O_RDONLY) = -1 ENOENT (No such file or directory)
[pid 15752] stat("/usr/lib/ssl/certs/c692a373.0", 0x7fffad4fc430) = -1 ENOENT (No such file or directory)
[pid 15752] stat("/usr/lib/ssl/certs/c692a373.0", 0x7fffad4fc500) = -1 ENOENT (No such file or directory)
[pid 15752] stat("/usr/lib/ssl/certs/653b494a.0", {st_mode=S_IFREG|0644, st_size=1261, ...}) = 0
[pid 15752] open("/usr/lib/ssl/certs/653b494a.0", O_RDONLY) = 10
[pid 15752] stat("/usr/lib/ssl/certs/653b494a.1", 0x7fffad4fc4b0) = -1 ENOENT (No such file or directory)
...
302
{"SERVER"=>"nginx", "CONTENT_TYPE"=>"text/html; charset=UTF-8", "CONTENT_LENGTH"=>"26", "EXPIRES"=>"Thu, 19 Nov 1981 08:52:00 GMT", ...}
""
```

To see a diff of the changes run:

```console
$ diff -u broken-monkey-patch.rb fixed-monkey-patch.rb
```

This repo also includes the two versions of the `ca-certificates` package
(before/after the CyberTrust root was removed).
