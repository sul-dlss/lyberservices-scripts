# Lyberservices Scripts

[![Build Status](https://travis-ci.org/sul-dlss/lyberservices-scripts.svg?branch=master)](https://travis-ci.org/sul-dlss/lyberservices-scripts)
[![Coverage Status](https://coveralls.io/repos/github/sul-dlss/lyberservices-scripts/badge.svg?branch=master)](https://coveralls.io/github/sul-dlss/lyberservices-scripts?branch=master)

A collection of Ruby scripts that may need access to
- objects before pre-assemble (thumper, smpl drives)
- dor workspaces (SDR objects before accessioning)
- stacks
- web-archiving-stacks
- preservation storage roots

These scripts are used by a small number of power users in the PSM group (Peter, for one.)

Note that we hope to retire this repo:
- if you are writing a new script, please surface it in #dlss-infrastructure channel to see if there is a different way to get the desired result, without adding to our maintenance burden.

This code was in the sul-dlss/pre-assembly git repo before pre-assembly became a Rails app.
After the Rails version of pre-assembly, this code was in the v3-legacy branch of the sul-dlss/pre-assembly git repo.

## Deployment

Regular capistrano deployment:

```bash
cap stage deploy # for lyberservices-test
cap prod deploy # for lyberservices-prod
```

## Running

0.  If you can, run your job using the pre-assembly web app: https://sul-preassembly-prod.stanford.edu/ instead of using these scripts.

1.  Gather information about your project, including:
    *   The location of the materials.  You will need read access to this
        location from the servers you will be accessioning in (e.g. test and
        production).
    *   Whether the objects are already registered or not.
    *   The location of any descriptive metadata.
    *   Whether you will be flattening the folder structure of each object
        when accessioning (e.g. discarding any folder structure provided to
        you in each object).
    *   The DRUID of the project's APO.
    *   The DRUID of the set object you will be associating your objects with
        (if any).
    *   If your objects are not yet registered and you have a manifest file in
        CSV format, make sure you have columns for sourceid, filename, and
        label.  See config/projects/manifest_template/TEMPLATE_manifest.csv
        for an example manifest.  See the "manifest" section below for more
        information.
    *   If you are using a manifest file in CSV format and want to create
        descriptive metadata, create a MODs XML template.  See the
        "descriptive metadata" section below for more details.


2.  Create a project-configuration YAML file using the data you gathered
    above. Store this file in a location where it can be accessed by the
    server (test or production). You should create a YAML file for each
    environment specifying the parameters as appropriate. Use the convention
    of `projectname_environment.yaml`, e.g. `revs_test.yaml`. If you have
    multiple collections to associate your objects with, you will need to run
    in multiple batches with multiple YAML files. You can add your collection
    name to the end of each YAML filename to keep track (e.g.
    `revs_test_craig.yaml`)

    The YAML file can be stored anywhere that is accessible to the server you
    are running the code on. However, for simplicity, we recommend you store
    the YAML at the root of your bundle directory, or create a new project
    folder, place your YAML file into it and then place your bundle directory
    into your new project folder. ***PLEASE DO NOT PLACE YOUR YAML FILE INTO THE
    lyberservices-scripts DIRECTORY ITSELF ANYWHERE ON THE SERVER. IT WILL BECOME HARD
    TO FIND AND BE SUBJECT TO DELETION WHEN NEW CODE IS DEPLOYED.***

    Example:

    *   Your content is on `/thumpers/dpgthumper-staing/Hummel`
    *   Create a YAML file at
        `/thumpers/dpgthumper-staging/Hummel/hummel_test.yaml`
    *   Move your content (if you can) into
        `/thumpers/dpgthumper-staging/Hummel/content`


    If you cannot move your content, be sure your YAML bundle discovery glob
    and/or regex are specific enough to correctly ignore your YAML file during
    discovery. Or, alternatively, place your YAML file in a location other
    than the bundle.

    *   See [`TEMPLATE.yaml`](config/projects/TEMPLATE.yaml) for a fully documented example of a
        configuration file.
    *   See [`manifest_noreg_example.yaml`](config/projects/manifest_noreg_example.yaml) for a specific example
        using a manifest.
    *   See [`reg_example.yaml`](config/projects/reg_example.yaml) for a specific example using a
        file system crawl.

3.  Check the permissions on the bundle directory, iteratively. You need read
    permissions on all the bundle directory folders and files. You need to
    have write permissions in the location you plan to write the log file too
    (often this cannot be the thumper drives since it is mounted as
    read-only).

4.  You may benefit from running some objects in a local or test environment.
    If your objects are already registered, this may require pre-registering a
    sample set in test as well as production using the same DRUIDs that are
    identified with your content. You may also have to move a small batch of
    test content to a location that is visible to sul-lyberservices-test.
    Since the thumper drives are not mounted on the test server, you can use
    the `/dor/content` mount on test for this purpose.

5.  Make sure you have an APO for your object, and that the
    administrativeMetadata data stream has the `<assemblyWF>` defined in it.
    If it does not, go to https://consul.stanford.edu/display/APO/Home and
    find the "Current FoXML APO template" link at the bottom of the page.
    Download and open the template, find the `<assembly>` node and copy it. Go
    to Fedora admin for each relevant environment (test/production) and this
    node to the administrativeMetadata stream. If you don't have this workflow
    defined in your APO, then the assembly robots will never operate and
    accessioning will not operate. This APO should be defined using the same
    DRUID in test and production if you intend to run in both locations.

6.  You can perform a dry discovery run to test your YAML configuration. This
    run will enumerate the discovered objects, tell you how many files were
    discovered in each object, check for filename uniqueness in each object,
    and confirm objects are registered with an APO (for projects where objects
    are pre-registered). This dry run is particularly important if you are
    flattening each object's folder structure during pre-assemble (e.g. each
    object has images in a '00' and '05' directory, but you don't want to
    retain those folders when accessioning), since you will want to check to
    make sure each file in a given object has unique filenames. For projects
    that use manifests for object discovery along with checksum files, you can
    optionally have checksums computed and confirmed. This is really only
    useful if you are staging content and not accessioning immediately (since
    the accessioning process will reconfirm checksums).

    First log into sul-lyberservices-test or -prod as needed, and then cd into
    the lyberservices-scripts directory, e.g.

```
        ssh scripts@sul-lyberservices-test.stanford.edu
        cd lyberservices-scripts/current
        ROBOT_ENVIRONMENT=test bin/discovery_report YAML_FILE
```

    You will probably want to run this against a specific environment so it
    can connect to DOR and confirm registration on the appropriate server,
    e.g:

```
        ROBOT_ENVIRONMENT=production bin/discovery_report YAML_FILE
```

    You will see a report containing:
    *   the total number of objects discovered
    *   the names of each discovered object along with the number of files
        which will be discovered in that object
    *   any entries (directories or files) in the bundle directory which will
        **not** be discovered based on your configuration.
    *   the total number and listing of any objects which have duplicate
        filenames.  You must resolve the duplicate filenames if you intend to
        flatten the folder structure when accessioning.
    *   for manifest style projects, the label and source id along with if all
        source IDs contained in the manifest are unique
    *   for manifest style projects, a listing of any folders/files present in
        the bundle directory that are not referenced in the manifest... some
        will be expected (such as a checksum file), but this will let you see
        if any expected images/data are missing from the manifest
    *   for SMPL style projects, a listing of the the number of files found in
        the content metadata manifest ... which will let you know if you it
        has correctly found the object in the `smpl_manifest.csv` file -- a 0
        would mean none were found or listed, which is a problem


    If any errors occur, they will be displayed and a total error count is
    shown at the bottom.

    To send the report to a CSV file for better sorting and viewing in Excel,
    send the output to a file using normal UNIX syntax, e.g.:

```
        ROBOT_ENVIRONMENT=production bin/discovery_report YAML_FILE > /full/path/to/report/filename.csv
```

    When sending output to a CSV, you will not see any terminal output while
    the report is running.

    Options for discovery report: You can add the following parameters after
    the YAML_FILE name. Note that adding each option may make the report time
    consuming, especially for large number of objects. Some options only work
    for certain styles of projects.

    `confirm_checksums`:
        for manifest style projects, will compute and confirm checksums
        against the checksum file if it exists -- useful it you are not
        accessioning immediately
    `check_sourceids`:
        for manifest style projects, will confirm source IDs are globally
        unique in DOR (sources ids area already checked for local uniqueness
        in the manifest)
    `no_check_reg`:
        for projects where objects are to be registered, DONT'T check if
        objects are registered and have APOs (assuming they are supposed to be
        registered already)
    `show_staged`:
        will show all files that will be staged (warning: will produce a lot
        of output if you have lots of objects with lots of files!)
    `show_smpl_cm`:
        will show content metadata that will be generated for each SMPL object
        using the supplied manifest (warning: will produce a lot of XML output
        if you have lots of objects with lots of files!)

    e.g.

```
        ROBOT_ENVIRONMENT=production bin/discovery_report YAML_FILE confirm_checksums check_sourceids > report.csv
```

7.  To run  locally:

```
# Normal run.  Will restart and crete a new log file, overwriting any existing log file for that project.
bin/pre-assemble YAML_FILE

# Run in resume mode, which will automatically pick up where left off based on the log file.  Passing the --resume flag overrides the actual value of resume from the YAML config.
bin/pre-assemble YAML_FILE --resume

# Run in limit mode (default of 200), which will automatically limit the number of items pre-assembled to 200 regardless of what is set in the YAML file.  Useful with resume.
bin/pre-assemble YAML_FILE --limit --resume

# Run in limit mode (set to 100), which will automatically limit the number of items pre-assembled regardless of what is set in the YAML file.  Useful with resume.
bin/pre-assemble YAML_FILE --limit=100 --resume
```

    Again, you can add `ROBOT_ENVIRONMENT=XXXX` to the beginning of the command
    to run in test, production or other modes as needed.

8.  Running in the production environment:

    *   Navigate to the production box, in the lyberservices-scripts area.
    *   Set the ROBOT_ENVIRONMENT=production.
    *   Run pre-assemble with nohup and in the background (&).
    *   Optionally, include the `--resume` option to override the resume
        parameter and set to true.
    *   Optionally, include the `--limit` option to override the limit
        paramater.  You can specify the limit, or you can let it default to
        200.


    See the example below:
```
        ssh scripts@sul-lyberservices-prod.stanford.edu
        cd /home/scripts/lyberservices-scripts/current
        ROBOT_ENVIRONMENT=production nohup bin/pre-assemble YAML_FILE &
```

    If you want to run multiple nohup jobs simultaneously, you can redirect
    screen output to a different log file:

```
        ROBOT_ENVIRONMENT=production nohup bin/pre-assemble YAML_FILE > another_nohup_filename.out 2>&1&
```

    Various ways to monitor progress:
    1.  The workflow grid in Argo, using your project tag to filter.
    2.  grep pid PROGRESS_LOG          # Using the filename defined in YAML
        progress_log_file.
    3.  tail -999f log/production.log  # Detailed logging info for the
        lyberservices-scripts project itself.
    4.  tail -999f nohup.out           # Errors, etc from unix output (or
        "another_nohup_filename.out" in the example above)


    Be sure to keep your progress log file somewhere useful and be aware if
    you restart pre-assemble without using the `--resume` switch, it will be
    overwritten. You will need the progress log for cleanup and restarting.

9.  Running in batch mode, automatically splitting a large run in groups of
    smaller jobs, using limits and resume:

```
    bin/batch_run YAML_CONFIG [LIMIT]
```

This will run pre-assemble multiple times sequentially, using resume and
limits, allowing the process to end and restart each time. This is useful to
prevent memory errors on the server when running large jobs.  It will
automatically compute the number of items remaining to be run, split the job
up into the number of jobs needed based on the limit you request, and then
sequentially run them. You will most likely want to run this in nohup mode,
sending the output to a file.  If no limit is specified, a default of 200 is
used.

    e.g.
```
    nohup ROBOT_ENVIRONMENT=production bin/batch_run /dor/staging/Revs/mail_box4.yaml > /dor/preassembly/revs/mailander_box4_batch.out 2>&1&
    # will run ALL of the incomplete items in that YAML file in the background, but in groups of the default size of 200, sending output for all runs to the mailander_box4_batch.out file

    nohup ROBOT_ENVIRONMENT=production bin/batch_run /dor/staging/Revs/mail_box4.yaml 100 > /dor/preassembly/revs/mailander_box4_batch.out 2>&1&
    # will run ALL of the incomplete items in that YAML file in the background, but in groups of 100, sending output for all runs to the mailander_box4_batch.out file
```

## Expert Cheatsheet

Here's a quick summary of the basic execution steps:

    # Goto VM and select environment
    % ssh scripts@lyberservices-prod
    % export ROBOT_ENVIRONMENT=production

    # Goto project directory and copy YAML and related files
    % cd MyProject
    % YAML=MyProject_$ROBOT_ENVIRONMENT.yaml
    % BUNDLEDIR=`grep bundle_dir: $YAML | cut -d \' -f2`
    % cp $YAML $BUNDLEDIR
    # optionally copy other required files to $BUNDLEDIR

    # Execute the pre-assemble
    % cd $HOME/lyberservices-scripts/current
    % bin/discovery_report $BUNDLEDIR/$YAML
    % bin/pre-assemble $BUNDLEDIR/$YAML

# Notes

The assembly robots will automatically create jp2 derivates from any TIFFs,
JP2s, or JPEGs. If you are working on a legacy project that has JP2s already
that were generated from source TIFFs, you should **not** stage those files
during pre-assemble, or else you will end up with two JP2s for each TIFF. You
can do this by using a regex to exclude .JP2 files or by only staging certain
subfolders. If you do stage the JP2 files and they have the same filename as
the TIFF (but with a different extension) they will be kept as is (i.e. they
will NOT have JP2s re-generated from the source TIFFs). If you do stage the
JP2 files and they have a different basename than the TIFFs, they WILL be
re-generated, and you will end up with two copies, in two different resources.

## Setting up code for local development

    # Clone project.
    git clone git@github.com:sul-dlss/lyberservices-scripts.git
    cd lyberservices-scripts

    Copy the default configs and use them for local and test.

      cp config/environments/test.example.rb config/environments/test.rb
      cp config/environments/test.example.rb config/environments/development.rb

    You will need to have a certificate to access DOR-test in order to run integration tests from your laptop.  The certificates are placed
    in your laptop's "config/certs" folder and are referenced in the "config/environments/test.rb" file.  Talk to DevOps to get a certificate.

    # Get needed gems.
    bundle install

    # Confirm that it's working by running the tests as described below.

    To make your life easier, it's easiest to put this in your bash profile so you don't need to identify each time you run a command on your laptop during development:

      export ROBOT_ENVIRONMENT=local

## Running tests

### Prerequisites

You need exiftool on your system in order to successfully run all of the
tests.

    RHEL: (RPM to install comming soon)
    Download latest version from:  http://www.sno.phy.queensu.ca/~phil/exiftool

        tar -xf Image-ExifTool-#.##.tar.gz
        cd Image-ExifTool-#.##
        perl Makefile.PL
        make test
        sudo make install

    If you are a mac user, use homebrew to install it (if you don't have homebrew installed, you really should: http://brew.sh/):
        brew install exiftool

To run all tests, use the command below.  Note that to run integration tests,
you will need to be connected to the VPN (even if on campus).

    bin/run_all_tests

To run the unit tests (fast) and the integration tests (slower) separately,
use the commands below.  As noted above, integration tests require VPN.

    bundle exec rspec spec        # no DOR access required, no VPN
    bundle exec rspec integration # DOR access required, VPN

## Environments

Use the ROBOT_ENVIRONMENT=xxxxx in front of commands to run in a specific
environment.  Current available environments are:

- local:   your laptop
- development:   development servers
- test:   test servers
- production:   production servers

The server environments define which instance of DOR is connected to, as well
as the workflow and other services. If you run in the incorrect environment,
you will find your objects registered in unexpected places, or you may run
into errors when objects you believe should be registered are not.

## Screen Command

If screen is installed on the server you are using (currently not in
production), another possibility instead of running nohup is to run using the
"screen" command.  (NOTE: currently, screen is not available in production).

Start a new screen by typing:

    $  screen

You can then start pre-assemble without nohup, just like you would locally:

    $  ROBOT_ENVIRONMENT=production bin/pre-assemble YAML_FILE

You can then detach from the screen by pressing ctrl-a, ctrl-d and then exit
from the server.

You can come back to your screen by re-logging into the server, and typing

    $ screen -r

You can also see a list of available screens by typing

    $ screen -list

For more info on screen, see http://kb.iu.edu/data/acuy.html

## Troubleshooting

### Seeing an error like this when you try to run pre-assemble or a discovery report?

```
Psych::SyntaxError: (<unknown>): mapping values are not allowed in this
context at line 37 column 14
```

It's probably because your YAML configuration file is malformed. YAML is very
picky, particularly in tabs, spacing and other formatting trickeries.  You verify
your YAML file inside `rails console` or `irb`:

```
bin/console yaml_config = '/full/path/to/your/config.yaml'
params = YAML.load(File.read yaml_config)
```

If you get a hash of values back, it parsed correctly.  If you get the
`Psych::SyntaxError`, it did not.  The line number referenced in the error
should help you locate the part of your file that is having issues.  Edit and
try loading the YAML again on the console to confirm.

1.  If you don't see all of your objects being discovered or no files are
    found in discovered objects, check the permissions on the bundle
    directory. You need read permissions on all the bundle directory folders
    and files.

2.  Be sure you are running on the correct server in the correct environment.
    See the "environment" section above.

3.  Be sure you have read access to the YAML file you created from the server
    you are running on.

4.  Be sure you have write access to the location you have specified for your
    progress log file. When running as scripts on the test and production
    machines, you will NOT have write access to the thumper drivers. You
    should store your progress log file elsewhere, such as /dor/preassembly

5.  Check to see if the assembly and accessioning robots are running in the
    environment you are using. See the "Starting Robots" section below. It is
    not recommended that you start robots in production without consulting the
    Lyberstructure team.

6.  If you don't see JP2s being created (or recreated) for your content, this
    is probably due to one of the following problems:

    1.  The content metadata generated by pre-assemble didn't set a resource
        type or set a resource type other than "image" or "page". Assembly
        will only create jp2s for images containing in resources marked as
        "image" or "page". Pre-assemble will do this automatically for
        :simple_image and :simple_book projects, but check the output of the
        content metadata to be sure.

    2.  The image was not a mimetype of 'image/jpeg' or 'image/tiff'.  Any
        other mimetype will be ignored.

    3.  Your input image was corrupt or missing a color space profile.  This
        will usually cause the jp2-create robot to fail and throw an error in
        that workflow step.

    4.  You had an existing JP2 in the directory that matched a tiff or jpeg.
        In this case the jp2-create robot will not overwrite any existing
        files just to be safe.

    5.  You had an existing JP2 in the directory that matched a DPG style
        filename (e.g. if you had existing tiff called `xx000yy1111_00_01.tif`
        and a jp2 called `xx000yy1111_05_01.jp2`), you will not get another jp2
        from that tiff even though there would not be a filename clash, under
        the principle that it refers to the same image).


7.  If 6b or 6c above, it is possible to spot check images to assess the
    problem:

        $ ssh scripts@lyberservices-prod
        $ cd ~/lyberservices-scripts/current
        $ ROBOT_ENVIRONMENT=production bin/console
        > a=Assembly::Image.new('/full/path/to/image')
        > a.jp2able? # (if "false" then diagnose the problem further)
        > a.exif['profiledescription'] # (if "nil" then it is missing color profile)
        > a.mimetype # (should be "image/tiff" or "image/jpeg")
        > a.width # should give you the image width
        > a.height # should give you image height

    It is possible to force add color profiles to a single image or all of the
    images in a given directory:
```
        source_img=Assembly::Image.new('/input/path_to_file.tif') # add to a single image
        source_img.add_exif_profile_description('Adobe RGB 1998')
```
    or
```
        Assembly::Images.batch_add_exif_profile_description('/full_path_to_tifs','Adobe RGB 1998')    # add to multiple images
```

8.  If you see incorrect content metadata being generated, note that if
    should_register = false, the 'Process : Content Type' tag for each
    existing object will be examined. If a known type is set in this tag, it
    will be used to create content metadata instead of the default set in
    [project_style](:content_structure). Check the tag for each object if the
    style is not matching what you have set in the YAML configuration file.
    Also note that if `content_md_creation[:style]` is set to 'none', then no
    content metadata will be generated.


## Restarting a job

If you have failed objects during your pre-assemble, these will either cause
pre-assemble to terminate immediately (if the failure is non-recoverable) or
it will continue and log the errors. The progress log file you specified in
your YAML configuration will contain information about which bundles failed.
You can re-start pre-assemble and ask it to re-try the failed objects and
continue with any other objects that it hadn't done yet. To do this, use the
`--resume` flag when you run pre-assemble:

```
    ROBOT_ENVIRONMENT=production bin/pre-assemble YAML_FILE --resume
```

## Post Accessioning Reports

Use [Argo](https://argo.stanford.edu/).

Two reports are available if you can't use Argo.  If you wish to use these
reports, both produce the following output, but differ in how they locate
objects to report on. The output for both reports is a CSV file in the "log"
folder of your checked out lyberservices-scripts code. Both will report on up to 50,000
rows and includes the following columns:

* druid
* label
* source_id
* dc:title
* published status
* shelved status
* PURL url
* total files in object
* number of files by file extension

### project tag report

The first report is called a `"project_tag_report"` and includes ALL objects in
DOR tagged with a specific project tag. This is useful for a global project
overview and is cumulative (i.e. as more objects are added with that tag, the
report will be bigger if run again).

```
ROBOT_ENVIRONMENT=production bin/project_tag_report PROJECT_TAG
```

where `PROJECT_TAG` is the Argo project tag (e.g. "Revs"). If your project tag
has spaces in it, be sure to use quotes, like this:

```
ROBOT_ENVIRONMENT=production bin/generate_collection_report "Stanford Oral History Project"
```

## Manifests

Manifests are a way of indicating which objects you will be accessioning. A
manifest file is a CSV, UTF-8 encoded file and works for projects which have
one file per object (container = one file in this case), or projects with many
files per object (container = folder in this case).

**WARNING**: if you export from Microsoft Excel, you may not get a properly
formatted UTF-8 CSV file. You should open any CSV that has been exported from
Excel in a text editor and re-save it in proper UTF-8 files (like TextMate on
a Mac).

There are a few columns required in the manifest, depending on whether `should_register` is `true` or `false`:

- `container`: container name (either filename or folder name) -- **required**
- `druid`: druid of object (**required** if `should_register` = `false`)
- `sourceid`: source ID (**required** if `should_register` = `true`)
- `label`: label (**required** if `should_register` = `true`)

The druids should include the "druid:" prefix (e.g. "druid:oo000oo0001" instead of "oo000oo0001").

The first line of the manifest is a header and specifies the column names.
Column names should not have spaces and it is easiest if they are all lower
case. These columns are used to register objects and indicate which file goes
with the object. If the container column specifies a filename, it should be
relative to the manifest file itself. You can have additional columns in your
manifest which can be used to create descriptive metadata for each object. See
the section below for more details on how this works.

The actual names of the columns above (except for "druid") can be set in the
YAML file.  The druid column **must** be called `"druid"`..

See the sample manifest file [`TEMPLATE_manifest.csv`](config/projects/manifest_template/TEMPLATE_manifest.csv)

## Descriptive Metadata

If descriptive metadata is supplied in a source known to common accessioning
(currently MDToolkit or Symphony), then no action is required during
pre-assemble other than ensuring your DRUIDs and/or barcodes match the ones in
MDToolkit or Symphony.

If you are supplying a manifest file instead of using object discovery via
file system crawling, then you can also create a descriptive metadata MODs
file for each object using content supplied in the manifest.  By creating a
template XML MODS file, placing with your YAML configuration file and ensuring
it's filename is indicated in your YAML configuration, you can tell
pre-assemble to generate a MODs file per object.  The generated MODs file
should be called "descMetadata.xml" and will be staged alongside the content.
This file is automatically picked up during common accessioning.

The MODs file is generated by taking the XML template you supply, and filling
in any `[[field]]` values in the template with the corresponding column from
the manifest.

For example, if your template has

```xml
<mods><title>[[description]]</title></mods>
```

and you have a column called "description" in your manifest and you have a row
with a value of "picture of me", you will get that value filled into your
template for that specific object:

```xml
<mods><title>picture of me</title></mods>
```

In addition, the entire MODs template is passed through an ERB parser,
allowing you to utilize Ruby code in the template using the standard
[ERB](http://ruby-doc.org/stdlib-1.9.3/libdoc/erb/rdoc/ERB.html) template `<%
%>` syntax.  This can be used to perform more complex operations.  If you
utilize Ruby code, you will have access to a special local variable called
'manifest_row', which is a hash of values for that row in the manifest, keyed
off the column names.  For example:

```xml
<mods><title><%= manifest_row[:description] %></title></mods>
```

will provide the same output as the previous example.  A full example of a
MODs template is provided at
config/projects/manifest_template/TEMPLATE_mods.xml

To use a different character encoding in your ERB template, put the following
at the top of your *template.xml*:

```xml
<%#-*- coding: UTF-8 -*-%>
<?xml version="1.0" encoding="UTF-8"?>
```

## Testing Descriptive Metadata Generation

If you would like to test your MODs template prior to actually accessioning,
you can run a "mods report", passing in the YAML config file, which references
your manifest and MODs template, and a writable output folder location.  The
report will then generate a MODs file for each row in your manifest so you can
examine the results.  You can limit the number of rows run by temporarily
modifying the "limit_n" parameter in the YAML file. Note that the output
folder MUST exist and must be writable.  Be aware it will become filled with
MODs files, one per object.  So if you have a large number of rows in your
manifest, you will end up with many files in your output directory.

ROBOT_ENVIRONMENT=production bundle exec bin/mods_report YAML_CONFIG_FILE
OUTPUT_DIRECTORY

## Accession of Specific Objects

For projects with a manifest (e.g. like Revs):

1.  Create a new manifest with only the objects you need accessioned.
2.  Create a new project config YAML file referencing the new manifest and
    write to a new progress log file.
3.  Run pre-assemble script.


For projects that do not use a manifest and which have their objects already
registered (e.g. like Rumsey):

1.  Create a new project config YAML file and set the parameter
    'accession_items' using either the 'only' or

'except' parameter as needed. You can include only specific objects (useful
when you only want to run a few objects) or you can exclude specific objects
(useful when you want to run most). Also set a different progress log file so
you can store the results of your second run separately. See the TEMPLATE.yaml for some examples.

1.  Run pre-assemble.



### Loading YAML Configuration

If you are working in the console, and want to read your YAML configuration
file (for example, to determine where your progress log file is located), you
can use the following methods to load the configuration into a ruby hash:

e.g.

```
$ ROBOT_ENVIRONMENT=test bin/console

config_filename='/thumpers/dpgthumper2-smpl/SC1017_SOHP/sohp_prod_accession.yaml'
config=YAML.load(IO.read(filename))
progress_filename=config['progress_log_file']
```

You can then use these values in other utility methods as needed.

### Finding Druids

If you want to find the druids from your progress log file that are either
completed or not completed, you can use a method that will give you an array
of relevant druids. You can then use this array in 'workflow_status' method
noted above or in the other utility methods.

e.g.
```
$ ROBOT_ENVIRONMENT=test bin/console

completed_druids=PreAssembly::Utils.get_druids_from_log('/dor/preassembly/sohp_accession_log.yaml',true)
failed_druids=PreAssembly::Utils.get_druids_from_log('/dor/preassembly/sohp_accession_log.yaml',false)

```

If you want to find druids by source_id, use the utility method
PreAssembly::Utils.get_druids_by_sourceid(source_ids=[]) to do this. You can then
use the array of druids in the other utility methods.

e.g.

    $ ROBOT_ENVIRONMENT=test bin/console

    source_ids=%w{foo:123 bar:456}
    druids=PreAssembly::Utils.get_druids_by_sourceid(source_ids)

## Remediation

### Basic Object Remediation

A basic object remediation framework is provided for mass remediating objects.

To use it, first decide how you will specify the list of druids.  You can
either manually specify with a CSV (see step 1 below), or use the pre-assemble
YAML log file if you are remediating a run from pre-assemble.

1.  For running a specific list of druids, create a CSV file containing a list
    of druids you wish to remediate, one line per druid, with a header column
    called "druid" or "Druid" (caps don't matter).

There can be other columns too -- they will be ignored.  They can be either
full druids (with the prefix) or just the PIDs.  Save it somewhere the
lyberservices-scripts code can read it.

e.g.
druid
druid:oo000oo0001
druid:oo000oo0002
oo000oo0003

1.  Create a ruby file that defines exactly how you need to remediate each
    object.  The ruby file will define a method that has access to the

fedora object and can perform any actions needed on the object.  The actual
loading, saving, and versioning of objects is handled by the framework - you
just need to define the actual logic needed to operate on the object.  The
file needs to have a specific format with two specific methods that must be
defined, one that determines if remediation will occur at all, and the second
indicates the type of remediation to perform.  An example file and its format
is shown in the file 'lib/remediation/remediate_project_example.rb' Don't edit
that file - copy it, and edit it somewhere the script can read it.

Note that you have access to 'equivalent-xml'
(https://github.com/mbklein/equivalent-xml) for comparing xml when deciding if
you need to remediate.  You also can use nokogiri. If you use equivalent-xml
be sure to require it at the top of your script.

1.  Run with the command below (presumably on the lyberservices-prod server,
    which has access to Fedora production, although you can also

run in test or development mode if you can access those environments).  Pass
in the either the CSV file with DRUIDs or the pre-assemble YAML file and the
Ruby file you generated in steps 1 and 2.  You will get two output files --
the first is a CSV file which includes columns indicating if remediation
succeeded, a message and a timestamp.  You will also get a .log file.  Each
file is named in the same way as the input file with _log.csv and _log.yml
appended to the filename and is placed in the same location.  This means you
should place the input CSV in be a location where the script will have write
access to that location (i.e. not on a thumper drive if you are on
lyberservices-prod).

Note that the _log.yml file is used to ensure that objects are not run through
remediation twice, so you should keep that file in the same location as the
input CSV if you need to resume a large remediation.  In each case, the file
will always be appended to.

ROBOT_ENVIRONMENT=production bin/remediate INPUT_FILE.CSV[or LOG_FILE.YAML]
REMEDIATE_LOGIC_FILENAME.rb

For long running actions, you can run in nohup mode

ROBOT_ENVIRONMENT=production nohup bin/remediate INPUT_FILE.CSV[or
LOG_FILE.YAML] REMEDIATE_LOGIC_FILENAME.rb &

The result will be some screen output and a detailed log file in .YML format
in the same location and with the same name as the input CSV file. The input
CSV file will also be updated with two additional columns - a status
indicating if remediation succeeded and a message. You can re-run the
remediation with the same CSV file and it will automatically skip already
completed objects - SO KEEP THE CSV FILE.

ROBOT_ENVIRONMENT=production bin/remediate INPUT_FILE.csv
REMEDIATE_LOGIC_FILENAME.rb [PAUSE_TIME_IN_SECONDS]

Finally, you can specify a pause time in seconds per object. This can be
useful for large remediation jobs that are a low priority, which allows them
to run at a slower pace and thus generating less concurrent load on the system
while other higher priority jobs are running concurrently.

### MODs Remediation

A custom script has already been written to handle the case of updating MODs
given a spreadsheet and a MODs template.  See the file
devel/update_mods_metadata.rb for more information.

### Custom Object Remediation

You can also build a fully customized remediation script that does not require
input DRUIDs in a CSV and can pass data to individual druids for more specific
remediation.  To do this, you will need to implement the logging or resume
capability you will need. You will also still implement your own project
specific Ruby file (as in step 2 above) but you will also implement your own
mechanism for generating druids to remediate and for logging their completion.

Within the lyberservices-scripts codebase, you will have access to the following
remediation class.   Pass it a druid and your remediation logic Ruby file, and
it will return you success or failure and a message.  You can also use the
built in logging methods to record success/failure to help with resuming.  You
can also optionally pass any data structure or object you need and have that
available in your custom method.

    project_file='my_remediation.rb'
    pid='druid:oo000oo0001'
    require project_file

    item=PreAssembly::Remediation::Item.new(pid,optionalDataStructure) # optionalDataStructure is some kind of object, string, hash, etc.
                                                                       # it will be made available to your "remediate_logic" method in
     	                                                                # the instance variable @data
    item.extend(RemediationLogic) # add in our project specific methods
    item.description='some description that will be added to any versions which are opened' # optional
    success=item.remediate # returns true or false
    puts item.message # some more info about what was done

Loop over your PIDs and log results as needed.  You can log to an output CSV
and/or a YML file if you wish, using the following methods

    item.log_to_progress_file(progress_log_file)  # pass in a fully qualified path to a YML file to append to
    item.log_to_csv(csv_out)   # pass in a fully qualified path to a CSV file to append to

You can read in completed druids from a progress_log_file you have previously
created using a class level method if you wish to check if a druid is already
completed.  Each of these calls gives you an array of druids.

    completed_druids=PreAssembly::Remediation::Item.get_druids(progress_log_file)
    failed_druids=PreAssembly::Remediation::Item.get_druids(progress_log_file,false)
    done if completed_druids.include?(pid)  # will give you a true or false if your current pid is already done
