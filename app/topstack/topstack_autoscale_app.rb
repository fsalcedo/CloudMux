require 'sinatra'
require 'fog'

class TopStackAutoscaleApp < ResourceApiBase

	before do
    params["provider"] = "topstack"
    params["service_type"] = "AutoScale"
    @service_long_name = "Auto Scale"
    @service_class = Fog::AWS::AutoScaling
    @autoscale = can_access_service(params)
  end

	#
	# Autoscale Groups
	#
  ##~ sapi = source2swagger.namespace("topstack_autoscale")
  ##~ sapi.swaggerVersion = "1.1"
  ##~ sapi.apiVersion = "1.0"
  ##~ sapi.models["Autoscale_Group"] = {:id => "Autoscale_Group", :properties => {:id => {:type => "string"}, :availability_zones => {:type => "string"}, :launch_configuration_name => {:type => "string"}, :max_size => {:type => "string"}, :min_size => {:type => "string"}}}
  ##~ sapi.models["Launch_Configuration"] = {:id => "Launch_Configuration", :properties => {:id => {:type => "string"}, :image_id => {:type => "string"}, :instance_type => {:type => "string"}}}
  
  ##~ a = sapi.apis.add
  ##~ a.set :path => "/api/v1/cloud_management/topstack/autoscale/autoscale_groups"
  ##~ a.description = "Manage Autoscale resources on the cloud (Topstack)"
  ##~ op = a.operations.add
  ##~ op.responseClass = "Autoscale_Group"
  ##~ op.set :httpMethod => "GET"
  ##~ op.summary = "Describe Autoscale Groups (Topstack cloud)"
  ##~ op.nickname = "describe_autoscale_groups"  
  ##~ op.parameters.add :name => "filters", :description => "Filters for instances", :dataType => "string", :allowMultiple => false, :required => false, :paramType => "query"
  ##~ op.errorResponses.add :reason => "Success, list of autoscale groups returned", :code => 200
  ##~ op.errorResponses.add :reason => "Invalid Parameters", :code => 400
  ##~ op.parameters.add :name => "cred_id", :description => "Cloud credential to use", :dataType => "string", :allowMultiple => false, :required => true, :paramType => "query"
  get '/autoscale_groups' do
		filters = params[:filters]
		if(filters.nil?)
			response = @autoscale.groups
		else
			response = @autoscale.groups.all(filters)
		end
		[OK, response.to_json]
	end
    
    get '/configurations/:id' do
		response = @autoscale.configurations.get(params[:id])
		[OK, response.to_json]
    end

  ##~ a = sapi.apis.add
  ##~ a.set :path => "/api/v1/cloud_management/topstack/autoscale/autoscale_groups"
  ##~ a.description = "Manage Autoscale resources on the cloud (Topstack)"
  ##~ op = a.operations.add
  ##~ op.responseClass = "Autoscale_Group"
  ##~ op.set :httpMethod => "POST"
  ##~ op.summary = "Create a new Autoscale Group (Topstack cloud)"  
  ##~ op.nickname = "create_autoscale_groups"
  ##~ sapi.models["CreateLaunchConfig"] = {:id => "CreateLaunchConfig", :properties => {:id => {:type => "string"}, :image_id => {:type => "string"}, :instance_type => {:type => "string"}}}
  ##~ op.parameters.add :name => "launch_configuration", :description => "Launch Configuration to use", :dataType => "CreateLaunchConfig", :allowMultiple => false, :required => true, :paramType => "body"
  ##~ sapi.models["CreateAutoscale"] = {:id => "CreateAutoscale", :properties => {:id => {:type => "string"}, :availability_zones => {:type => "Array", :items => {:$ref => "string"}}, :launch_configuration_name => {:type => "string"}, :max_size => {:type => "string"}, :min_size => {:type => "int"}, :AutoScalingGroupName => {:type => "string"}}}
  ##~ op.parameters.add :name => "autoscale_group", :description => "Autoscale Group Options", :dataType => "CreateAutoscale", :allowMultiple => false, :required => true, :paramType => "body"
  ##~ op.errorResponses.add :reason => "Success, new Autoscale Group created", :code => 200
  ##~ op.errorResponses.add :reason => "Invalid Parameters", :code => 400
  ##~ op.parameters.add :name => "cred_id", :description => "Cloud credential to use", :dataType => "string", :allowMultiple => false, :required => true, :paramType => "query"
  post '/autoscale_groups' do
    json_body = body_to_json_or_die("body" => request, "args" => ["autoscale_group","launch_configuration"])
    can_create_instance("cred_id" => params[:cred_id], "action" => "use_image", "options" => {:image_id => json_body["instance"]["image_ref"]} )
    max_instances = 0
    max_instances = json_body["autoscale_group"]["MaxSize"].to_i - 1
    can_create_instance("cred_id" => params[:cred_id], "action" => "create_autoscale", "options" => {:instance_count=>max_instances.to_i} )
		begin
      region = get_creds(params[:cred_id]).cloud_account.default_region
			launch_config = json_body["launch_configuration"]
			autoscale_group = json_body["autoscale_group"]
      autoscale_group['AvailabilityZones'] = [region]
      @autoscale.configurations.create(launch_config)
			response = @autoscale.groups.create(autoscale_group)
			if(json_body["trigger"])
				set_monitor_interface(params[:cred_id], params[:region])
				trigger = json_body["trigger"]
				#create scale up policy and metric alarm
        scale_up_name = autoscale_group["AutoScalingGroupName"] + "ScaleUpPolicy"
        up_policy = @autoscale.put_scaling_policy("ChangeInCapacity", autoscale_group["AutoScalingGroupName"], scale_up_name, trigger["scale_increment"]).body["PutScalingPolicyResult"]["PolicyARN"]
				up_options = {
					"AlarmName" => autoscale_group["AutoScalingGroupName"] + trigger["trigger_measurement"] + "UpAlarm",
					"AlarmActions" => [up_policy],
					"Dimensions" => [{"Name" => "AutoScalingGroupName", "Value" => autoscale_group["AutoScalingGroupName"]}],
					"ComparisonOperator" => "GreaterThanThreshold",
					"Namespace" => "AWS/EC2",
					"EvaluationPeriods" => 1,
					"MetricName" => trigger["trigger_measurement"],
					"Period" => trigger["measure_period"],
					"Statistic" => trigger["statistic"],
					"Threshold" => trigger["upper_threshold"],
					"Unit" => trigger["unit"]
				}
				@monitor.put_metric_alarm(up_options)
	   			#create scale down policy and metric alarm
	   			scale_down_name = autoscale_group["AutoScalingGroupName"] + "ScaleDownPolicy"
	   			down_policy = @autoscale.put_scaling_policy("ChangeInCapacity", autoscale_group["AutoScalingGroupName"], scale_down_name, trigger["scale_decrement"]).body["PutScalingPolicyResult"]["PolicyARN"]
	   			down_options = {
	   				"AlarmName" => autoscale_group["AutoScalingGroupName"] + trigger["trigger_measurement"] + "DownAlarm",
					"AlarmActions" => [down_policy],
					"Dimensions" => [{"Name" => "AutoScalingGroupName", "Value" => autoscale_group["AutoScalingGroupName"]}],
					"ComparisonOperator" => "LessThanThreshold",
					"Namespace" => "AWS/EC2",
					"EvaluationPeriods" => 1,
					"MetricName" => trigger["trigger_measurement"],
					"Period" => trigger["measure_period"],
					"Statistic" => trigger["statistic"],
					"Threshold" => trigger["lower_threshold"],
					"Unit" => trigger["unit"]
	   			}
	   			@monitor.put_metric_alarm(down_options)
			end
			[OK, response.to_json]
		rescue => error
			handle_error(error)
		end
	end
    
    post '/autoscale_groups/:id' do
          json_body = body_to_json(request)
  		if(json_body.nil? || json_body["launch_configuration"].nil? || json_body["autoscale_group"].nil? || params[:cred_id].nil?)
  			[BAD_REQUEST]
  		else
  			begin
                region = get_creds(params[:cred_id]).cloud_account.default_region
  				launch_config = json_body["launch_configuration"]
  				autoscale_group = json_body["autoscale_group"]
                autoscale_group['AvailabilityZones'] = [region]
                
                launch_config['id'] = launch_config['id'] + ' ' + Time.new.to_s
                autoscale_group['LaunchConfigurationName'] = launch_config['id']
                
                @autoscale.configurations.create(launch_config)
  				response = @autoscale.update_auto_scaling_group(params[:id],autoscale_group)

  				if(json_body["trigger"])
  					set_monitor_interface(params[:cred_id], params[:region])
  					trigger = json_body["trigger"]
  					#create scale up policy and metric alarm
  		            scale_up_name = autoscale_group["AutoScalingGroupName"] + "ScaleUpPolicy"
  		            up_policy = @autoscale.put_scaling_policy("ChangeInCapacity", autoscale_group["AutoScalingGroupName"], scale_up_name, trigger["scale_increment"]).body["PutScalingPolicyResult"]["PolicyARN"]
  					up_options = {
  						"AlarmName" => autoscale_group["AutoScalingGroupName"] + trigger["trigger_measurement"] + "UpAlarm",
  						"AlarmActions" => [up_policy],
  						"Dimensions" => [{"Name" => "AutoScalingGroupName", "Value" => autoscale_group["AutoScalingGroupName"]}],
  						"ComparisonOperator" => "GreaterThanThreshold",
  						"Namespace" => "AWS/EC2",
  						"EvaluationPeriods" => 1,
  						"MetricName" => trigger["trigger_measurement"],
  						"Period" => trigger["measure_period"],
  						"Statistic" => trigger["statistic"],
  						"Threshold" => trigger["upper_threshold"],
  						"Unit" => trigger["unit"]
  					}
  					@monitor.put_metric_alarm(up_options)
  		   			#create scale down policy and metric alarm
  		   			scale_down_name = autoscale_group["AutoScalingGroupName"] + "ScaleDownPolicy"
  		   			down_policy = @autoscale.put_scaling_policy("ChangeInCapacity", autoscale_group["AutoScalingGroupName"], scale_down_name, trigger["scale_decrement"]).body["PutScalingPolicyResult"]["PolicyARN"]
  		   			down_options = {
  		   				"AlarmName" => autoscale_group["AutoScalingGroupName"] + trigger["trigger_measurement"] + "DownAlarm",
  						"AlarmActions" => [down_policy],
  						"Dimensions" => [{"Name" => "AutoScalingGroupName", "Value" => autoscale_group["AutoScalingGroupName"]}],
  						"ComparisonOperator" => "LessThanThreshold",
  						"Namespace" => "AWS/EC2",
  						"EvaluationPeriods" => 1,
  						"MetricName" => trigger["trigger_measurement"],
  						"Period" => trigger["measure_period"],
  						"Statistic" => trigger["statistic"],
  						"Threshold" => trigger["lower_threshold"],
  						"Unit" => trigger["unit"]
  		   			}
  		   			@monitor.put_metric_alarm(down_options)
  				end
  				[OK, response.to_json]
  			rescue => error
  				handle_error(error)
  			end
  		end
  	end
	
  ##~ a = sapi.apis.add
  ##~ a.set :path => "/api/v1/cloud_management/topstack/autoscale/autoscale_groups/:id/spin_down"
  ##~ a.description = "Update Autoscale Group on the cloud (Topstack)"
  ##~ op = a.operations.add
  ##~ op.responseClass = "Autoscale_Group"
  ##~ op.set :httpMethod => "POST"
  ##~ op.summary = "Update Autoscale Group on the cloud (Topstack)"  
  ##~ op.nickname = "spin_down"
  ##~ op.parameters.add :name => "id", :description => "ID to use", :dataType => "string", :allowMultiple => false, :required => true, :paramType => "path"
  ##~ op.errorResponses.add :reason => "Success, Autoscale Group returned", :code => 200
  ##~ op.errorResponses.add :reason => "Invalid Parameters", :code => 400
  ##~ op.parameters.add :name => "cred_id", :description => "Cloud credential to use", :dataType => "string", :allowMultiple => false, :required => true, :paramType => "query"
  post '/autoscale_groups/:id/spin_down' do
		begin
			response = @autoscale.update_auto_scaling_group(params[:id], {"MinSize" => 0, "MaxSize" => 0, "DesiredCapacity" => 0})
			[OK, response.to_json]
		rescue => error
			handle_error(error)
		end
	end
	
  ##~ a = sapi.apis.add
  ##~ a.set :path => "/api/v1/cloud_management/topstack/autoscale/autoscale_groups/:id"
  ##~ a.description = "Delete Autoscale Group on the cloud (Topstack)"
  ##~ op = a.operations.add
  ##~ op.responseClass = "Autoscale_Group"
  ##~ op.set :httpMethod => "DELETE"
  ##~ op.summary = "Delete Autoscale Group on the cloud (Topstack)"  
  ##~ op.nickname = "spin_down"
  ##~ op.parameters.add :name => "id", :description => "ID to use", :dataType => "string", :allowMultiple => false, :required => true, :paramType => "path"
  ##~ op.errorResponses.add :reason => "Success, Autoscale Group Deleted", :code => 200
  ##~ op.errorResponses.add :reason => "Invalid Parameters", :code => 400
  ##~ op.parameters.add :name => "cred_id", :description => "Cloud credential to use", :dataType => "string", :allowMultiple => false, :required => true, :paramType => "query"
  delete '/autoscale_groups/:id' do
		begin
			policies = @autoscale.describe_policies({"AutoScalingGroupName" => params[:id]}).body["DescribePoliciesResult"]["ScalingPolicies"]
      policies.each do |t|
				@autoscale.delete_policy(params[:id], t["PolicyName"]) unless t["PolicyName"].nil?
			end
			response = @autoscale.groups.get(params[:id]).destroy
			launch_config = @autoscale.configurations.get(params[:id]+"-lc")
			if ! launch_config.nil?
      # Feature not implemented
		  # 		launch_config.destroy
			end
			[OK, response.to_json]
		rescue => error
			handle_error(error)
		end
	end

	def set_monitor_interface(cred_id, region)
		cloud_cred = get_creds(cred_id)
		if cloud_cred.nil?
			return nil
		else
			# Find Monitor service endpoint
            endpoint = cloud_cred.cloud_account.cloud_services.where({"service_type"=>"Monitor"}).first
            fog_options = {:aws_access_key_id => cloud_cred.access_key, :aws_secret_access_key => cloud_cred.secret_key}
            fog_options.merge!(:host => endpoint[:host], :port => endpoint[:port], :path => endpoint[:path], :scheme => endpoint[:protocol])
            @monitor = Fog::AWS::CloudWatch.new(fog_options)
		end
	end
end
