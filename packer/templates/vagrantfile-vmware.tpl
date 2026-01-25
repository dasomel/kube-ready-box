Vagrant.configure("2") do |config|
  config.vm.base_mac = nil

  config.vm.provider "vmware_desktop" do |vmware|
    vmware.vmx["memsize"] = "2048"
    vmware.vmx["numvcpus"] = "2"
  end
end
