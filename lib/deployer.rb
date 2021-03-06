require 'haikunator'
require 'azure_mgmt_resources'

class Deployer
  DEPLOYMENT_PARAMETERS = {
      dnsLabelPrefix:       Haikunator.haikunate(100),
      vmName:               'azure-deployment-sample-vm'
  }

  # Initialize the deployer class with subscription, resource group and public key. The class will raise an
  # ArgumentError under two conditions, if the public key path does not exist or if there are empty values for
  # Tenant Id, Client Id or Client Secret environment variables.
  #
  # @param [String] subscription_id the subscription to deploy the template
  # @param [String] resource_group the resource group to create or update and then deploy the template
  # @param [String] pub_ssh_key_path the path to the public key to be used to authentication
  def initialize(subscription_id, resource_group, pub_ssh_key_path = File.expand_path('~/.ssh/id_rsa.pub'))
    @resource_group = resource_group
    @subscription_id = subscription_id
    raise ArgumentError.new("The path: #{pub_ssh_key_path} does not exist.") unless File.exist?(pub_ssh_key_path)
    @pub_ssh_key = File.read(pub_ssh_key_path)
    provider = MsRestAzure::ApplicationTokenProvider.new(
        ENV['AZURE_TENANT_ID'],
        ENV['AZURE_CLIENT_ID'],
        ENV['AZURE_CLIENT_SECRET'])
    credentials = MsRest::TokenCredentials.new(provider)
    @client = Azure::ARM::Resources::ResourceManagementClient.new(credentials)
    @client.subscription_id = @subscription_id
  end

  # Deploy the template to a resource group
  def deploy
    # ensure the resource group is created
    params = Azure::ARM::Resources::Models::ResourceGroup.new.tap do |rg|
      rg.location = 'westus'
    end
    @client.resource_groups.create_or_update(@resource_group, params)

    # build the deployment from a json file template from parameters
    template = File.read(File.expand_path(File.join(__dir__, '../templates/template.json')))
    deployment = Azure::ARM::Resources::Models::Deployment.new
    deployment.properties = Azure::ARM::Resources::Models::DeploymentProperties.new
    deployment.properties.template = JSON.parse(template)
    deployment.properties.mode = Azure::ARM::Resources::Models::DeploymentMode::Incremental

    # build the deployment template parameters from Hash to {key: {value: value}} format
    deploy_params = DEPLOYMENT_PARAMETERS.merge(sshKeyData: @pub_ssh_key)
    deployment.properties.parameters = Hash[*deploy_params.map{ |k, v| [k,  {value: v}] }.flatten]

    # put the deployment to the resource group
    @client.deployments.create_or_update(@resource_group, 'azure-sample', deployment)
  end

  # delete the resource group and all resources within the group
  def destroy
    @client.resource_groups.delete(@resource_group)
  end

  def dns_prefix
    DEPLOYMENT_PARAMETERS[:dnsLabelPrefix]
  end

  def print_properties(resource)
    puts "\tProperties:"
    resource.instance_variables.sort.each do |ivar|
      str = ivar.to_s.gsub /^@/, ''
      if resource.respond_to? str.to_sym
        puts "\t\t#{str}: #{resource.send(str.to_sym)}"
      end
    end
    puts "\n\n"
  end

end