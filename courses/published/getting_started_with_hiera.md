# Getting started with Hiera - Part 1

When you first start using Puppet, you might include configuration details in
your Puppet code.  For example, when setting up a database server, you might
hard-code the hostname of the server in the Puppet manifest. As your Puppet
implementation grows, this can become unmanageable. Making a small change to an
system might mean making changes across multiple parts of your Puppet code.
Hiera offers a robust and straightforward way to separate data from code.

The name 'Hiera' stands for hierarchy, but the most basic functional Hiera
config doesn't have to be hierachical.  Let's set up a simple flat lookup using
Hiera.  

Imagine you want to set a default message of the day on your servers.  You
could do this with the following Puppet code:

<pre>
$message = "Welcome to ${::hostname}. Don't break anything!"
file { '/etc/motd':
  ensure  => file,
  owner   => 'root',
  group   => 'root',
  mode    => '0644',
  content => $message,
}
</pre>

This works just fine, but the more you hard-code data into your Puppet code,
the harder it is to maintain.  What if you wanted to share that code with
someone outside your company? You'd have to remember to go in and clean out any
potentially sensitive data across your entire codebase.

Even with the simplest configuration, Hiera offers a robust way to separate that
data from your code.

Using Hiera, the code would look this this:
<pre>
$message = hiera('message')
file { '/etc/motd':
  ensure  => file,
  owner   => 'root',
  group   => 'root',
  mode    => '0644',
  content => $message
}
</pre>

You'll need to tell Hiera where to find the data, you can do this by creating a
file called `/etc/puppetlabs/puppet/hiera.yaml`:

<pre>
---
:backends: "yaml"
:yaml:
  :datadir: "/etc/puppetlabs/code/hieradata/"
  :hierarchy:
    - "common"
</pre>

Since this is a simple example, our hierarchy only has one level, "common". In
future lessons, we'll add some more levels. We'll keep "common" as the base of
the hierarchy as a place to hold global defaults. 

We still need to add the actual data. Do this by creating a file called
`common.yaml` in the `datadir` that's listed in `hiera.yaml`

`common.yaml` looks like this:
<pre>
---
message: "Welcome to ${::hostname}. Don't break anything!"
</pre>

Now that you have a sense of the basic config, try adding another key/value
pair to the `common.yaml` on the practice VM. Experiment with changing things
to see what results you get. Don't worry if you break something, just reload
the page to get a fresh machine.

To test out Hiera, you can use the `hiera` command line tool.  For example, to
lookup the value of "message", type `hiera message`.

When you're ready to move on, just click to the next section, the practice
machine will shut down automatically when you're done.

If you need a refresher in the Linux command line or in using the vim text
editor, take a look at those courses before proceeding.

## Exercise 1

Add a second key.


## Getting started with Hiera - Part 2

Hiera is pretty handy for keeping all of your data in one place, when you add a
level of hierarchy it becomes a lot more powerful.

Let's imagine you have two webservers, one is in your "production" environment
and one is in your "development" environment.  They are mostly the same, but
they need to use different DNS servers.

Without Hiera, your code might look like this:
<pre>
case $environment {
  'production': {
    $dns_server = 'proddns.puppet.vm'
  }
  'development': {
    $dns_server = 'devdns.puppet.vm'
  }
}
profile::dns_server {
  dns_server => $dns_server,
}
</pre>

This is simple enough for two servers. What if you add developer workstations
or another pre-production test environment? What if there are more
configuration differences between environments? The code can quickly get out of
control.

Let's look at how the code would appear in using Hiera:
<pre>
$dns_server = hiera('$dns_server')
profile::dns_server {
  dns_server => $dns_server,
}
</pre>

So what happened to the details? Now they're in two separate files, one for
each environment. They go in the same directory as `common.yaml`

Here's the production environment, we'll call it `production.yaml`
<pre>
---
dns_server: 'proddns.puppet.vm'
</pre>

And here's the dev environment, we'll call it `development.yaml`
<pre>
---
dns_server: 'devdns.puppet.vm'
</pre>

There's one place you need to change things, that's in your `hiera.yaml`.
You'll have to add another level to the hierarchy, above "common". Since we
want to use the value of the environment and not just the word "environment",
we'll need to add some special syntax.

Here's what the `hiera.yaml` needs to look like:
<pre>
---
:backends: "yaml"
:yaml:
  :datadir: "/etc/puppetlabs/code/hieradata"
  :hierarchy:
    - "%{environment}"
    - "common"
</pre>

Before we go further, why not try out what you've just learned? To tell the
command line `hiera` tool what value to use for `environment` just add it after
the key.

For example, to check the `dns_server` in the `production` environment, you
would use this command:

<pre>
hiera dns_server environment=production
</pre>

Try adding another environment called "qa", or even another level in the
hierarchy that's based on the `hostname` fact instead of `environment`.

## Exercise 2

Per environment Hiera

## Getting started with Hiera - Part 3

In the last lesson, we assigned the value of a variable using the `hiera()`
function and that variable was passed into a profile called `profile::dns`.
There is actually a better pattern for doing this, you can use the `hiera()`
function inside the class definition as the default parameter.

So when you define your `profile::dns` class it would look something like this:
<pre>
class profile::dns (
  $dns_server = hiera('dns_server')
) {
...
}  
</pre>

Since you wouldn't need to specify the `dns_server` parameter when you declare
the class, you can now include the `profile::dns` class with this code:
<pre>
include profile::dns
</pre>

But there's a problem. As you write more code like this, it becomes very easy
to lose track of which key/value pair applies to what class. The standard
convention is to use the name of class as part of the Hiera key like this:
`profile::dns::dns_server`.

This convention isn't just to make things easy to remember. Since Puppet 3,
there has been a feature called "Automatic Parameter Lookup" which means you
can leave out the Hiera call from the class definition. When the Puppet Master
compiles a catalog for your node it will check in Hiera before falling back to
the defaults.

In our example, let's assume there's a default value in profile::params:

<pre>
class profile::dns (
  $dns_server = $profile::params::dns_server
) {
...
}
</pre>

Now if there is a value in Hiera for `profile::dns::dns_server` the master will
use that, otherwise it will fall back to what's in `params.pp` of the "profile"
module. You may be thinking that Hiera understands namespaces, so it's somehow
filing the `dns_server` key under `profile::dns`, but that isn't right. Hiera
just uses the entire string `profile::dns::dns_server` as a single key.

As always, you can still override both defaults by specifying the
parameter yourself:

<pre>
class {'profile::dns':
  dns_server => 'globaldns.puppet.vm',
}
</pre>

Automatic Parameter Lookup is one of the ways in which Hiera can seem "magical"
to new users.  To help you get the hang of how it works, we've created a few
example classes that take parameters. Play around with it until it makes sense.

For this exercise, you'll be running `puppet agent -t` against a Puppet Master.
For convenience, we've made a link to your agent's environment on the master to
the `/root/puppetcode` directory on the agent node.  You can just declare the
example classes in the `default` node definition in
`/root/puppetcode/manifests/site.pp` and run puppet on your agent node.

Remember, if you break something, just reload the page and you'll get a fresh
environment.

## Exercise 3

Automatic Parameter Lookup
Pre-loaded example code


## Getting started with Hiera - Part 4

Before we move on to other ways of using Hiera data, let's take a look at few
of the configuration options in `hiera.yaml` So far, all of our Hiera data
files have been in a single directory. Depending on the complexity of your
data, this might be fine, but chances are you'll want to split things up.

For example, what if you have some configuration that only applies to
individual nodes? It isn't best practice, but sometimes you need to have a
couple of unique snowflakes in your infrastructure.

To support per-node configuration in Hiera, it's best to use the `clientcert`
fact.  By default this is the hostname of the node when the certificate was
generated and it's the unique name that the master knows the node by.  It's
more secure than using the hostname since a compromised node could report a
false hostname but can't fake another node's certificate.

In order to keep all those YAML files from cluttering up our hieradata folder,
we'll put them in a subfolder called "nodes" and add that level to the top of
our hierarchy in hiera.yaml:

<pre>
---
:backends: "yaml"
:yaml:
  :datadir: "/etc/puppetlabs/code/hieradata"
  :hierarchy:
    - "nodes/%{clientcert}"
    - "%{environment}"
    - "common"
</pre>

Let's go back to the message of the day example to try this one out. Imagine
you've got two developers, Jane and Bob. They each have a development server
for testing out their code.

Jane wants to see some useful information when she logs in, so
`nodes/jane.puppet.vm.yaml` looks like this:
<pre>
---
message: "Welcome to ${::hostname}. ${::osfamily} - ${::memorysize}"
</pre>

Bob is more territorial, so `nodes/bob.puppet.vm.yaml` looks like this:
<pre>
---
message: "This is Bob's development server. Don't touch anything, or else!"
</pre>

Since you can't log in to the actual machines, you can test out Hiera's
response to different hostnames by passing in `clientcert` as a variable to the
`hiera` command line tool:
<pre>
hiera message clientcert=jane.puppet.vm
</pre>

This isn't limited to a single directory, you can have multiple subdirectories.
You can even use have more complex levels of the hierarchy. For example, if you
have multiple datacenters each with a development and production environment,
you could use a custom fact of "datacenter" to have something like this:
<pre>
---
:backends: "yaml"
:yaml:
  :datadir: "/etc/puppetlabs/code/hieradata"
  :hierarchy:
    - "nodes/%{clientcert}"
    - "%{datacenter}/%{environment}"
    - "common"
</pre>

To give a more complex configuration a try you can pass multiple parameters to
the `hiera` command line tool.  For example, to find out the MOTD on the
development servers in the Portland datacenter, you would use this command:
<pre>
hiera message environment=development datacenter=portland
</pre>

We've set up a complex hierarchy, explore a bit, add some keys/value pairs, and
see if you can get a sense of how Hiera behaves. What happens if you use a
hostname that doesn't have a corresponding YAML file? How about an environment
that doesn't exist? What if you set up conflicting values? 

If this is starting to seem overwhelming, don't worry. Hierachies of more than
a few levels are unusual in practice, so don't add complexity if you don't need
it. Even this example is probably more complexity than most users will ever
need.

## Exercise 4

Complex hierarchies


## Getting started with Hiera - Part 5

Now that we've seens what possible with complex hierarchies, let's take a look
at some other ways of interacting with Hiera data. What if you want to combine
data from multiple levels of the hierarchy?

For example, you have a list of software packages that you want installed on
every server and some that depend on the environment. If you had to specify
that at every level of the hierarchy it would lead to a lot of duplicate data.

Thankfully, Hiera is more intelligent than that. Let's look at how this could
play out in a hierarchy with three levels. At the top, we have the per-node
configuration. Let's just set one up for Bob's dev server in
'nodes/bob.puppet.vm.yaml':
<pre>
---
package_list:
  - emacs
</pre>

All of the other developers use vim, so let's make sure the development.yaml
has that package along with some other useful things:
<pre>
---
package_list:
  - vim
  - gcc
  - cowsay
</pre>

But in production, we don't want anything extra, so instead of vim we'll just
have vi and leave out the other packages:
<pre>
---
package_list:
  - vi
</pre>

Finally, at the bottom of the hierarchy we have a few packages that should be
installed on every machine in common.yaml:
<pre>
---
package_list:
  - dig
  - ssh
  - fortune
</pre>

Unfortunately, using the `hiera()` function will only return the result from a
single level in the hierarchy. To correctly merge across multiple levels of the
hierarchy, we'll need to use `hiera_array()`:

<pre>
$packages = hiera_array('package_list')
package { $packages:
  ensure => present,
}
</pre>

The best way to understand `hiera_array()` is to just dig in and try it out.
It's pretty easy to test by using the command line `hiera` tool, just use the
`-a` argument. For example to see what packages are installed on Bob's dev
machine you would use this command:
<pre>
hiera -a package_list environment=development clientcert=bob.puppet.vm.yaml
</pre>

and the result would be:
<pre>
["fortune","dig","ssh","vim","gcc","cowsay","emacs"]
</pre> 


We've set up these example files and a few more on the practice machine, try a
few permutations until you have a feel for how `hiera_array()` works.

## Exercise 5

hiera_array() examples.
