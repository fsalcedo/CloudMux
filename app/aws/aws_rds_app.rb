require 'sinatra'
require 'fog'

class AwsRdsApp < ResourceApiBase
	#
	# Volumes
	#
	get '/databases/describe' do
		rds = get_rds_interface(params[:cred_id], params[:region])
		if(rds.nil?)
			[BAD_REQUEST]
		else
			filters = params[:filters]
			if(filters.nil?)
				response = rds.servers
			else
				response = rds.servers.all(filters)
			end
			[OK, response.to_json]
		end
	end
	
	put '/databases/create' do
		rds = get_rds_interface(params[:cred_id], params[:region])
		if(rds.nil?)
			[BAD_REQUEST]
		else
			json_body = body_to_json(request)
			if(json_body.nil?)
				[BAD_REQUEST]
			else
				begin
					response = rds.servers.create(json_body["relational_database"])
					[OK, response.to_json]
				rescue => error
					handle_error(error)
				end
			end
		end
	end
	
	delete '/databases/delete' do
		rds = get_rds_interface(params[:cred_id], params[:region])
		if(rds.nil?)
			[BAD_REQUEST]
		else
			json_body = body_to_json(request)
			if(json_body.nil? || json_body["relational_database"].nil?)
				[BAD_REQUEST]
			else
				begin
					response = rds.servers.get(json_body["relational_database"]["id"]).destroy
					[OK, response.to_json]
				rescue => error
					handle_error(error)
				end
			end
		end
	end

	get '/engine_versions/describe' do
		rds = get_rds_interface(params[:cred_id], params[:region])
		if(rds.nil?)
			[BAD_REQUEST]
		else
			begin
				engine_versions = rds.describe_db_engine_versions.body['DescribeDBEngineVersionsResult']['DBEngineVersions'].as_json
				engine_versions.each do |v|
					v.each_pair do |name, value|
						v[name] = value.strip
					end
				end
				[OK, engine_versions.to_json]
			rescue => error
				handle_error(error)
			end
		end
	end

	get '/parameter_groups/describe' do
		rds = get_rds_interface(params[:cred_id], params[:region])
		if(rds.nil?)
			[BAD_REQUEST]
		else
			filters = params[:filters]
			if(filters.nil?)
				response = rds.parameter_groups
			else
				response = rds.parameter_groups.all(filters)
			end
			[OK, response.to_json]
		end
	end

	get '/security_groups/describe' do
		rds = get_rds_interface(params[:cred_id], params[:region])
		if(rds.nil?)
			[BAD_REQUEST]
		else
			filters = params[:filters]
			if(filters.nil?)
				response = rds.security_groups
			else
				response = rds.security_groups.all(filters)
			end
			[OK, response.to_json]
		end
	end

	def get_rds_interface(cred_id, region)
		if(cred_id.nil?)
			return nil
		else
			cloud_cred = get_creds(cred_id)
			if cloud_cred.nil?
				return nil
			else
				if region.nil? or region == "undefined" or region == ""
					return Fog::AWS::RDS.new({:aws_access_key_id => cloud_cred.access_key, :aws_secret_access_key => cloud_cred.secret_key})
				else
					return Fog::AWS::RDS.new({:aws_access_key_id => cloud_cred.access_key, :aws_secret_access_key => cloud_cred.secret_key, :region => region})
				end
			end
		end
	end
end