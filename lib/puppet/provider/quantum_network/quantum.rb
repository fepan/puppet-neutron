require File.join(File.dirname(__FILE__), '..','..','..',
                  'puppet/provider/quantum')

Puppet::Type.type(:quantum_network).provide(
  :quantum,
  :parent => Puppet::Provider::Quantum
) do
  desc <<-EOT
    Quantum provider to manage quantum_network type.

    Assumes that the quantum service is configured on the same host.
  EOT

  commands :quantum => 'quantum'

  mk_resource_methods

  def self.has_provider_extension?
    list_quantum_extensions.include?('provider')
  end

  def has_provider_extension?
    self.class.has_provider_extension?
  end

  has_feature :provider_extension if has_provider_extension?

  def self.has_router_extension?
    list_quantum_extensions.include?('router')
  end

  def has_router_extension?
    self.class.has_router_extension?
  end

  has_feature :router_extension if has_router_extension?

  def self.quantum_type
    'net'
  end

  def self.instances
    list_quantum_resources(quantum_type).collect do |id|
      attrs = get_quantum_resource_attrs(quantum_type, id)
      new(
        :ensure                    => :present,
        :name                      => attrs['name'],
        :id                        => attrs['id'],
        :admin_state_up            => attrs['admin_state_up'],
        :provider_network_type     => attrs['provider:network_type'],
        :provider_physical_network => attrs['provider:physical_network'],
        :provider_segmentation_id  => attrs['provider:segmentation_id'],
        :router_external           => attrs['router:external'],
        :shared                    => attrs['shared'],
        :tenant_id                 => attrs['tenant_id']
      )
    end
  end

  def self.prefetch(resources)
    networks = instances
    resources.keys.each do |name|
      if provider = networks.find{ |net| net.name == name }
        resources[name].provider = provider
      end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    network_opts = Array.new

    if @resource[:shared]
      network_opts << '--shared'
    end

    if @resource[:tenant_name]
      network_opts << "--tenant_id=#{get_tenant_id}"
    elsif @resource[:tenant_id]
      network_opts << "--tenant_id=#{@resource[:tenant_id]}"
    end

    if @resource[:provider_network_type]
      network_opts << \
        "--provider:network_type=#{@resource[:provider_network_type]}"
    end

    if @resource[:provider_physical_network]
      network_opts << \
        "--provider:physical_network=#{@resource[:provider_physical_network]}"
    end

    if @resource[:provider_segmentation_id]
      network_opts << \
        "--provider:segmentation_id=#{@resource[:provider_segmentation_id]}"
    end

    if @resource[:router_external]
      network_opts << "--router:external=#{@resource[:router_external]}"
    end

    results = auth_quantum('net-create', '--format=shell',
                           network_opts, resource[:name])

    if results =~ /Created a new network:/
      @network = Hash.new
      results.split("\n").compact do |line|
        @network[line.split('=').first] = \
          line.split('=', 2)[1].gsub(/\A"|"\Z/, '')
      end

      @property_hash = {
        :ensure                    => :present,
        :name                      => resource[:name],
        :id                        => @network['id'],
        :admin_state_up            => @network['admin_state_up'],
        :provider_network_type     => @network['provider:network_type'],
        :provider_physical_network => @network['provider:physical_network'],
        :provider_segmentation_id  => @network['provider:segmentation_id'],
        :router_external           => @network['router:external'],
        :shared                    => @network['shared'],
        :tenant_id                 => @network['tenant_id'],
      }
    else
      fail("did not get expected message on network creation, got #{results}")
    end
  end

  def get_tenant_id
    @tenant_id ||= model.catalog.resource( \
     "Keystone_tenant[#{resource[:tenant_name]}]").provider.id
  end

  def destroy
    auth_quantum('net-delete', name)
    @property_hash[:ensure] = :absent
  end

  def admin_state_up=(value)
    auth_quantum('net-update', "--admin_state_up=#{value}", name)
  end

  def shared=(value)
    auth_quantum('net-update', "--shared=#{value}", name)
  end

  def router_external=(value)
    auth_quantum('net-update', "--router:external=#{value}", name)
  end

  [
   :provider_network_type,
   :provider_physical_network,
   :provider_segmentation_id,
   :tenant_id,
  ].each do |attr|
     define_method(attr.to_s + "=") do |value|
       fail("Property #{attr.to_s} does not support being updated")
     end
  end

end