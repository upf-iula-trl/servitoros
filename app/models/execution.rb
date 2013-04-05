class Execution < ActiveRecord::Base

  acts_as_model_with_status({new: 1 , initialized: 2, running: 3, finished: 4, error: 100}, :default => :new, :column => :status)
  attr_accessible :name, :description, :user_id

  serialize :results

  belongs_to :user

  validates :name, :presence => true

  def run!
    self.taverna_id = create_taverna_run
    self.status = :initialized
    save
  end

  def wait
    until finished?
      sleep 1
      update_status
      update_results
    end
    status
  end

  def update_status
    return unless taverna_id
    self.status = server_run.status
  end

  def update_status!
    update_status
    save
  end

  def update_results
    return unless finished?

    results = {}
    server_run.output_ports.each do |port_id, port|
      outputs = []
      port.value.size.times do |i|
        outputs << {:value => port.value[i], :size => port.size[i]}
      end
      results[port_id] = outputs
    end
    self.results = results
  end

  def update_results!
    update_results
    save
  end

  def finished?
    status == :finished
  end

  def running?
    status == :running
  end

  def initialized?
    status == :initialized
  end

  private

  def server
    @server ||= T2Server::Server.new(server_uri, connection_params)
  end

  def server_run
    @server_run ||= server.run(taverna_id, credentials)
  end

  def workflow
    File.read(Rails.root.join("config","freeling_tagging_for_crawled_data_610788.t2flow"))
  end

  def credentials
    username = Rails.configuration.taverna_server.username
    password = Rails.configuration.taverna_server.password
    T2Server::HttpBasic.new(username, password)
  end

  def connection_params
    conn_params = T2Server::DefaultConnectionParameters.new
    conn_params[:verify_peer] = Rails.configuration.taverna_server.verify_peer
    conn_params[:ssl_version] = Rails.configuration.taverna_server.ssl_version
    conn_params
  end

  def server_uri
    T2Server::Util.strip_uri_credentials(Rails.configuration.taverna_server.uri).first
  end

  def setup_inputs run
    inputs = {'language' => 'es'}
    files = {'input_urls' => Rails.root.join('config', 'input1.txt').to_s}

    in_ports = run.input_ports
    in_ports.each_value do |port|
      input = port.name
      if inputs.include? input
        port.value = inputs[input]
      elsif files.include? input
        port.file = files[input]
      end
    end
  end

  def create_taverna_run
    new_taverna_id = nil
    T2Server::Run.create(server_uri, workflow, credentials, connection_params) do |run|
      setup_inputs(run)
      run.start

      new_taverna_id = run.identifier
    end
    new_taverna_id
  end

end
