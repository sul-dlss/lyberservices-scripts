require 'assembly'

describe Assembly::Image do

  it "can be initialized" do
    @ai = Assembly::Image.new :file_name => 'foo.tif', :full_path => 'tmp/foo.tif'
  end

end