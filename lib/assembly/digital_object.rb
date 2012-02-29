module Assembly

  class DigitalObject

    include Assembly::Logging

    attr_accessor(
      :project_name,
      :apo_druid_id,
      :collection_druid_id,
      :label,
      :source_id,
      :druid,
      :pid,
      :images,
      :content_metadata_yml,
      :content_md_file_name,
      :public_attr,
      :uuid,
      :registration_info,
      :druid_tree_dir
    )

    def initialize(params = {})
      @project_name          = params[:project_name]
      @apo_druid_id          = params[:apo_druid_id]
      @collection_druid_id   = params[:collection_druid_id]
      @label                 = params[:label]
      @source_id             = { params[:project_name] => params[:source_id] }
      @druid                 = nil
      @pid                   = ''
      @images                = []
      @content_metadata_yml  = ''
      @content_md_file_name  = 'content_metadata.xml'
      @publish_attr          = { :preserve => 'yes', :shelve => 'no', :publish => 'no' }
      @uuid                  = UUIDTools::UUID.timestamp_create.to_s
      @registration_info     = nil
      @druid_tree_dir        = ''
    end

    def get_druid_from_suri()   Dor::SuriService.mint_id                           end
    def register_in_dor(params) Dor::RegistrationService.register_object params    end
    def delete_from_dor(pid)    Dor::Config.fedora.client["objects/#{pid}"].delete end
    def druid_tree_mkdir(dir)   FileUtils.mkdir_p dir                              end

    def add_image(params)
      @images.push Image::new(params)
    end

    def assemble(stager, staging_dir)
      log "  - assemble(#{@source_id})"
      claim_druid
      register
      stage_images stager, staging_dir
      generate_content_metadata
      write_content_metadata
      initialize_assembly_workflow
    end

    def claim_druid
      log "    - claim_druid()"
      @pid   = get_druid_from_suri
      @druid = Druid.new @pid
    end

    def register
      log "    - register(#{@pid})"
      @registration_info = register_in_dor(registration_params)
    end

    def registration_params
      {
        :object_type  => 'item',
        :admin_policy => @apo_druid_id,
        :source_id    => @source_id,
        :pid          => @pid,
        :label        => "#{@project_name}_#{@label || @druid.id}",
        :tags         => ["Project : #{@project_name}"],
        :other_ids    => { 'uuid' => @uuid },
      }
    end

    def stage_images(stager, base_target_dir)
      # Copy or move images to staging directory.
      @images.each do |img|
        @druid_tree_dir = @druid.path base_target_dir
        log "    - staging(#{img.full_path}, #{@druid_tree_dir})"
        druid_tree_mkdir @druid_tree_dir
        stager.call img.full_path, @druid_tree_dir
      end
    end

    def generate_content_metadata
      # Store expected checksums and other provider-provided metadata
      # in a skeletal version of contentMetadata.
      # TODO: generate_content_metadata: persist misc info from data provider.
      log "    - generate_content_metadata_yml()"
      @content_metadata_yml = {
        :contentMetadata => {
          :objectId => @druid.id,
          :resource => cm_resource,
        }
      }.to_yaml
    end

    def cm_resource
      seq = 0
      @images.map { |img|
        seq += 1
        fh = { "id" => img.file_name }.merge @publish_attr
        {
            :id       => "#{@druid.id}_#{seq}",
            :label    => "Image #{seq}",
            :sequence => seq.to_s,
            :file     => fh,
        }
      }
    end

    def write_content_metadata(file_handle=nil)
      # TODO: write_content_metadata: spec.
      log "    - write_content_metadata()"
      unless file_handle
        file_name   = File.join @druid_tree_dir, @content_md_file_name
        file_handle = File.open(file_name, 'w')
      end
      file_handle.puts @content_metadata_yml
    end

    def initialize_assembly_workflow
      # Add common assembly workflow to the object, and put the object in the first state.
      # TODO: initialize_assembly_workflow: implement and spec.
    end

    def unregister
      log "  - unregister(#{@pid})"
      delete_from_dor @pid
      @registration_info = nil
    end

  end

end
