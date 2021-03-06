# encoding: UTF-8
require 'dor/services/client'

module PreAssembly

  class DigitalObject

    include PreAssembly::Logging

    # include any project specific files
    Dir[File.dirname(__FILE__) + '/project/*.rb'].each {|file| include "PreAssembly::Project::#{File.basename(file).gsub('.rb','').camelize}".constantize }

    INIT_PARAMS = [
      :container,
      :unadjusted_container,
      :stageable_items,
      :object_files,
      :project_style,
      :project_name,
      :apply_tag,
      :apo_druid_id,
      :set_druid_id,
      :file_attr,
      :bundle_dir,
      :staging_dir,
      :desc_md_template_xml,
      :init_assembly_wf,
      :content_md_creation,
      :staging_style,
      :smpl_manifest
    ]

    OTHER_ACCESSORS = [
      :pid,
      :druid,
      :label,
      :manifest_row,
      :source_id,
      :content_md_file,
      :technical_md_file,
      :desc_md_file,
      :content_md_xml,
      :technical_md_xml,
      :desc_md_xml,
      :pre_assem_finished,
      :content_structure
    ]

    (INIT_PARAMS + OTHER_ACCESSORS).each { |p| attr_accessor p }

    ####
    # Initialization.
    ####

    def initialize(params = {})
      INIT_PARAMS.each { |p| instance_variable_set "@#{p.to_s}", params[p] }
      @file_attr ||= params[:publish_attr]
      setup
    end

    def setup
      @pid                 = ''
      @druid               = nil
      @label               = Settings.default_label
      @source_id           = nil
      @manifest_row        = nil

      @content_md_file     = CONTENT_MD_FILE
      @technical_md_file   = TECHNICAL_MD_FILE
      @desc_md_file        = DESC_MD_FILE
      @content_md_xml      = ''
      @technical_md_xml    = ''
      @desc_md_xml         = ''


      @pre_assem_finished = false
      @content_structure  = (@project_style ? @project_style[:content_structure] : 'file')

    end

    def stager(source,destination)
      if @staging_style.nil? || @staging_style == 'copy'
        FileUtils.cp_r source, destination
      else
        FileUtils.ln_s source, destination, :force=>true
      end
    end

    # map the object type to content metadata creation styles supported by the assembly-objectfile gem
    # @return [Symbol] a metadata creation styles supported by the assembly-objectfile gem
    def content_md_creation_style
      # if this object needs to be registered or has no content type tag for a registered object, use the default set in the YAML file
      return default_content_md_creation_style if @project_style[:should_register] || !@project_style[:content_tag_override]

      # if the object is already registered and there is a object_type and we allow overrides, use it if we know what it means (else use the default)
      # set this object's content_md_creation_style
      {
        Cocina::Models::Vocab.image => :simple_image,
        Cocina::Models::Vocab.object => :file,
        Cocina::Models::Vocab.book => :simple_book,
        Cocina::Models::Vocab.manuscript => :simple_book,
        Cocina::Models::Vocab.map => :map,
        Cocina::Models::Vocab.three_dimensional => :'3d'
      }.fetch(object_type, default_content_md_creation_style)
    end

    # @return [Symbol]
    def default_content_md_creation_style
       @project_style[:content_structure].to_sym
    end

    # compute the base druid tree folder for this object
    def druid_tree_dir
      @druid_tree_dir ||=  DruidTools::Druid.new(@druid.id,@staging_dir).path()
    end

    def druid_tree_dir=(value)
      @druid_tree_dir=value
    end

    # the content subfolder
    def content_dir
      @content_dir ||= File.join(druid_tree_dir,'content')
    end

    # the metadata subfolder
    def metadata_dir
      @metadata_dir ||=  File.join(druid_tree_dir,'metadata')
    end

    ####
    # The main process.
    ####

    def pre_assemble(desc_md_xml=nil)

      @desc_md_template_xml = desc_md_xml

      log "  - pre_assemble(#{@source_id}) started"
      determine_druid

      register
      stage_files
      generate_content_metadata unless @content_md_creation[:style].to_s == 'none'
      generate_technical_metadata
      generate_desc_metadata
      start_accession
      log "    - pre_assemble(#{@pid}) finished"
    end


    ####
    # Determining the druid.
    ####

    def determine_druid
      # NOTE:  PR https://github.com/sul-dlss/lyberservices-scripts/pull/42 removed the option to get it from suri;
      #   if needed probably need to retool slightly to use registration service instead
      k = @project_style[:get_druid_from]
      log "    - determine_druid(#{k})"
      @pid   = method("get_pid_from_#{k}").call
      @druid = DruidTools::Druid.new @pid
    end

    def get_pid_from_manifest
      @manifest_row[:druid]
    end

    def get_pid_from_druid_minter
      DruidMinter.next
    end

    def get_pid_from_container
      "druid:#{container_basename}"
    end

    # @return [String] one of the values from Cocina::Models::DRO::TYPES
    def object_type
      object_client.find.type
    rescue Dor::Services::Client::NotFoundResponse
      ''
    end

    def object_client
      @object_client ||= Dor::Services::Client.object(pid)
    end

    def apo_matches_exactly_one?(apo_pids)
      n = 0
      apo_pids.each { |pid| n += 1 if pid == @apo_druid_id }
      n == 1
    end

    def container_basename
      File.basename(@container)
    end


    ####
    # Registration and other Dor interactions.
    ####

    def register
      return unless @project_style[:should_register]
      log "    - register(#{@pid})"
      register_in_dor(registration_params)
    end

    def register_in_dor(params)
      with_retries(max_tries: Settings.num_attempts, rescue: Exception, handler: PreAssembly.retry_handler('REGISTER_IN_DOR', method(:log), params)) do
        result = begin
          Dor::Services::Client.objects.register params: params
        rescue Exception => e
          source_id="#{@project_name}:#{@source_id}"
          log "      ** REGISTER FAILED ** with '#{e.message}' ... deleting object #{@pid} and source id #{source_id} and trying attempt #{i} of #{Settings.num_attempts} in #{Settings.sleep_time} seconds"
          delete_objects_from_workspace_by_source_id(source_id)
          nil
        end

        raise PreAssembly::UnknownError unless result.class == Dor::Item
        result
      end
    end

    def delete_objects_from_workspace_by_source_id(source_id)
      sourceid_pids = Dor::SearchService.query_by_id(source_id)
      all_pids= sourceid_pids << @pid
      all_pids.each do |pid|
        begin
          Dor::SearchService.solr.delete_by_id(pid)  # should be unnecessary, but handles an edge case where the object is not in Fedora, but is in Solr
          Dor::Config.fedora.client["objects/#{pid}"].delete
        rescue Exception => e
          log "      ... could not delete object with #{pid} or source id #{source_id} : #{e.message} ..."
        end
      end
      Dor::SearchService.solr.commit
    end

    def registration_params
      tags=["Project : #{@project_name}"]
      tags << @apply_tag unless @apply_tag.blank?
      {
        :object_type   => 'item',
        :admin_policy  => @apo_druid_id,
        :source_id     => { @project_name => @source_id },
        :collection_id => @set_druid_id,
        :pid           => @pid,
        :label         => @label.blank? ? Settings.default_label : @label,
        :tag           => tags,
      }
    end

    ####
    # Staging files.
    ####

    def stage_files
      # Create the druid tree within the staging directory,
      # and then copy-recursive all stageable items to that area.
      log "    - staging(druid_tree_dir = #{druid_tree_dir.inspect})"
      create_object_directories
      @stageable_items.each do |si_path|
        log "      - staging(#{si_path}, #{content_dir})", :debug
        # determine destination of staged file by looking to see if it is a known datastream XML file or not
        destination = METADATA_FILES.include?(File.basename(si_path).downcase) ? metadata_dir : content_dir
        stager si_path, destination
      end
    end

    ####
    # Technical metadata combined file for SMPL.
    ####
    def generate_technical_metadata

      create_technical_metadata
      write_technical_metadata

    end

    def create_technical_metadata
      # create technical metadata for smpl projects only
      return unless @content_md_creation[:style].to_s == 'smpl'

      tm = Nokogiri::XML::Document.new
      tm_node = Nokogiri::XML::Node.new("technicalMetadata", tm)
      tm_node['objectId']=@pid
      tm_node['datetime']=Time.now.utc.strftime("%Y-%m-%d-T%H:%M:%SZ")
      tm << tm_node

      # find all technical metadata files and just append the xml to the combined technicalMetadata
      current_directory=Dir.pwd
      FileUtils.cd(File.join(@bundle_dir,container_basename))
      tech_md_filenames=Dir.glob("**/*_techmd.xml").sort
      tech_md_filenames.each do |filename|
         tech_md_xml = Nokogiri::XML(File.open(File.join(@bundle_dir,container_basename,filename)))
         tm.root << tech_md_xml.root
      end
      FileUtils.cd(current_directory)
      @technical_md_xml=tm.to_xml

    end

    def write_technical_metadata
      # write technical metadata out to a file only if it exists
      return if @technical_md_xml.blank?

      file_name = File.join metadata_dir, @technical_md_file
      log "    - write_technical_metadata_xml(#{file_name})"
      create_object_directories
      File.open(file_name, 'w') { |fh| fh.puts @technical_md_xml }
    end

    ####
    # Content metadata.
    ####
    def generate_content_metadata

      create_content_metadata
      write_content_metadata

    end

    def create_content_metadata
      # Invoke the contentMetadata creation method used by the project
      # The name of the method invoked must be "create_content_metadata_xml_#{content_md_creation--style}", as defined in the YAML configuration
      # Custom methods are defined in the project_specific.rb file

      # if we are not using a standard known style of content metadata generation, pass the task off to a custom method
      if !['default','filename','dpg','none'].include? @content_md_creation[:style].to_s

        @content_md_xml = method("create_content_metadata_xml_#{@content_md_creation[:style]}").call

      elsif @content_md_creation[:style].to_s != 'none' # and assuming we don't want any contentMetadata, then use the Assembly gem to generate CM

        # otherwise use the content metadata generation gem
        params={:druid=>@druid.id,:objects=>content_object_files,:add_exif=>false,:bundle=>@content_md_creation[:style].to_sym,:style=>content_md_creation_style}

        params.merge!(:add_file_attributes=>true,:file_attributes=>@file_attr.stringify_keys) unless @file_attr.nil?

        @content_md_xml = Assembly::ContentMetadata.create_content_metadata(params)

      end

    end

    def write_content_metadata
      # write content metadata out to a file
      return if @content_md_creation[:style].to_s == 'none'
      file_name = File.join metadata_dir, @content_md_file
      log "    - write_content_metadata_xml(#{file_name})"
      create_object_directories

      File.open(file_name, 'w') { |fh| fh.puts @content_md_xml }

      # NOTE: This is being skipped because it now removes empty nodes, and we need an a node like this: <file id="filename" /> when first starting with contentMetadat
      #        If this node gets removed, then nothing works.  - Peter Mangiafico, October 3, 2015
      # mods_xml_doc = Nokogiri::XML(@content_md_xml) # create a nokogiri doc
      # normalizer = Normalizer.new
      # normalizer.normalize_document(mods_xml_doc.root) # normalize it
      # File.open(file_name, 'w') { |fh| fh.puts mods_xml_doc.to_xml } # write out normalized result

    end

    def content_object_files
      # Object files that should be included in content metadata.
      @object_files.reject { |ofile| ofile.exclude_from_content }.sort
    end

    ####
    # Descriptive metadata.
    ####

    def generate_desc_metadata
      # Do nothing for bundles that don't suppy a template.
      return unless @desc_md_template_xml
      create_desc_metadata_xml
      write_desc_metadata
    end

    def create_desc_metadata_xml
      log "    - create_desc_metadata_xml()"

      # Note that the template uses the variable name `manifest_row`, so we set it here
      manifest_row = @manifest_row

      # XML escape all of the entries in the manifest row so they won't break the XML
      manifest_row.each {|k,v| manifest_row[k]=Nokogiri::XML::Text.new(v,Nokogiri::XML('')).to_s if v }

      # ensure access with symbol or string keys
      manifest_row = manifest_row.with_indifferent_access

      # Run the XML template through ERB.
      template     = ERB.new(@desc_md_template_xml, nil, '>')
      @desc_md_xml = template.result(binding)

      # The @manifest_row is a hash, with column names as the key.
      # In the template, as a conviennce we allow users to put specific column placeholders inside
      # double brackets: "blah [[column_name]] blah".
      # Here we replace those placeholders with the corresponding value
      # from the manifest row.
      @manifest_row.each { |k,v| @desc_md_xml.gsub! "[[#{k}]]", v.to_s.strip }
      true

    end

    def write_desc_metadata
      file_name = File.join metadata_dir, @desc_md_file
      log "    - write_desc_metadata_xml(#{file_name})"
      create_object_directories
      File.open(file_name, 'w') { |fh| fh.puts @desc_md_xml }
    end

    def create_object_directories
      FileUtils.mkdir_p druid_tree_dir unless File.directory?(druid_tree_dir)
      FileUtils.mkdir_p metadata_dir unless File.directory?(metadata_dir)
      FileUtils.mkdir_p content_dir unless File.directory?(content_dir)
    end


    private

    ####
    # Versioning for a re-accession.
    ####

    def openable?
      version_client.openable?
    end

    def version_client
      object_client.version
    end

    def current_object_version
      @current_object_version ||= version_client.current.to_i
    end

    def start_accession
      return unless @init_assembly_wf
      version_params =
        {
          significance: 'major',
          description: 'lyberservices-scripts re-accession',
          opening_user_name: 'lyberservices-scripts'
        }
      object_client.accession.start(version_params)
    end
  end
end
