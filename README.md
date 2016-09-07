gca_website_builder
=================

Web server for pulling from github and updating static content

The only endpoint is /update_project/{project_name}

e.g. curl -XPOST http://localhost:8001/update_project/hipsci

The process is basically this:

1. Queries the rate limiter to find out if the project is already updating
  * Queues a new job and exits if a job is already queued
2. Uses the GitUpdater module to pull updates from git
3. Uses the Jekyll module to build the static content from the git repo
4. Uses the Rsyncer module to copy the jekyll _site directory to the webserver directories
5. Uses the ElasticSitemapIndexer to put the static content into elasticsearch. This enables site search.
6. Uses the PubSubHubBub module to announce updates to the rss feeds. This triggers automatic tweets.
7. Repeat 2-6 if a new job has been queued since the update began

Steps 2-6 get executed in a forked process because they are blocking.

Errors get emailed to users, set in the config file

Install
=======

    ./etc/init.d/website_updater install
 
This installs the following to the ./local directory:
 
1. cpan modules
2. Ensembl git tools
3. git (because it's not installed on our VMs by default)

Run the installation command from a login node with the same linux distribution as our VM, i.e. from a rh-6 login machine
