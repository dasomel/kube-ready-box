<?xml version="1.0"?>
<Envelope ovf:version="2.0" xml:lang="en-US" xmlns="http://schemas.dmtf.org/ovf/envelope/2" xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/2" xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData" xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:vbox="http://www.virtualbox.org/ovf/machine" xmlns:epasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_EthernetPortAllocationSettingData.xsd" xmlns:sasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_StorageAllocationSettingData.xsd">
  <References>
    <File ovf:id="file1" ovf:href="${VM_NAME}-disk001.vmdk"/>
  </References>
  <DiskSection>
    <Info>List of the virtual disks used in the package</Info>
    <Disk ovf:capacity="${DISK_SIZE_BYTES}" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" vbox:uuid="${disk_uuid}"/>
  </DiskSection>
  <NetworkSection>
    <Info>Logical networks used in the package</Info>
    <Network ovf:name="NAT">
      <Description>Logical network used by this appliance.</Description>
    </Network>
  </NetworkSection>
  <VirtualSystem ovf:id="${VM_NAME}">
    <Info>A virtual machine</Info>
    <OperatingSystemSection ovf:id="94">
      <Info>The kind of installed guest operating system</Info>
      <Description>Ubuntu_64</Description>
      <vbox:OSType ovf:required="false">Ubuntu_arm64</vbox:OSType>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements for a virtual machine</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemIdentifier>${VM_NAME}</vssd:VirtualSystemIdentifier>
        <vssd:VirtualSystemType>virtualbox-2.2</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:Caption>2 virtual CPUs</rasd:Caption>
        <rasd:Description>Number of virtual CPUs</rasd:Description>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>2</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:AllocationUnits>MegaBytes</rasd:AllocationUnits>
        <rasd:Caption>${MEMORY} MB of memory</rasd:Caption>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>${MEMORY}</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Caption>sataController0</rasd:Caption>
        <rasd:Description>SATA Controller</rasd:Description>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>AHCI</rasd:ResourceSubType>
        <rasd:ResourceType>20</rasd:ResourceType>
      </Item>
      <StorageItem>
        <sasd:AddressOnParent>0</sasd:AddressOnParent>
        <sasd:Caption>disk1</sasd:Caption>
        <sasd:Description>Disk Image</sasd:Description>
        <sasd:HostResource>ovf:/disk/vmdisk1</sasd:HostResource>
        <sasd:InstanceID>4</sasd:InstanceID>
        <sasd:Parent>3</sasd:Parent>
        <sasd:ResourceType>17</sasd:ResourceType>
      </StorageItem>
      <EthernetPortItem>
        <epasd:AutomaticAllocation>true</epasd:AutomaticAllocation>
        <epasd:Caption>Ethernet adapter on 'NAT'</epasd:Caption>
        <epasd:Connection>NAT</epasd:Connection>
        <epasd:InstanceID>5</epasd:InstanceID>
        <epasd:ResourceSubType>virtio</epasd:ResourceSubType>
        <epasd:ResourceType>10</epasd:ResourceType>
      </EthernetPortItem>
    </VirtualHardwareSection>
    <vbox:Machine ovf:required="false" version="1.20-macosx" uuid="{${vm_uuid}}" name="${VM_NAME}" OSType="Ubuntu_arm64" snapshotFolder="Snapshots">
      <ovf:Info>Complete VirtualBox machine configuration in VirtualBox format</ovf:Info>
      <Hardware>
        <Memory RAMSize="${MEMORY}"/>
        <Firmware type="EFI">
          <SmbiosUuidLittleEndian enabled="true"/>
          <AutoSerialNumGen enabled="true"/>
        </Firmware>
        <Network>
          <Adapter slot="0" enabled="true" type="virtio">
            <NAT localhost-reachable="true"/>
          </Adapter>
        </Network>
        <AudioAdapter useDefault="true" driver="CoreAudio" enabled="true"/>
        <Clipboard/>
        <StorageControllers>
          <StorageController name="SATA" type="AHCI" PortCount="30" useHostIOCache="false" Bootable="true" IDE0MasterEmulationPort="0" IDE0SlaveEmulationPort="1" IDE1MasterEmulationPort="2" IDE1SlaveEmulationPort="3">
            <AttachedDevice type="HardDisk" hotpluggable="false" port="0" device="0">
              <Image uuid="{${disk_uuid}}"/>
            </AttachedDevice>
          </StorageController>
        </StorageControllers>
      </Hardware>
      <Platform architecture="ARM">
        <RTC localOrUTC="UTC"/>
        <Chipset type="ARMv8Virtual"/>
        <CPU count="2"/>
        <arm>
          <CPU/>
        </arm>
      </Platform>
    </vbox:Machine>
  </VirtualSystem>
</Envelope>
