module Auth
    def Auth.validate(cred_id,service_name,action,options = nil)
        val = Validator.new(cred_id,service_name,action,options)
        val.policies.each    do |policy|
            if ! val.validatePolicy(policy)
                return false
            end
        end
        return true
    end

    def Auth.find_account(cloud_credential_id)
        return nil if cloud_credential_id.nil?
        account = Account.where({"cloud_credentials._id"=>Moped::BSON::ObjectId.from_string(cloud_credential_id.to_s)}).first
        (account.nil? ? nil : account)
    end

    def Auth.password_validate(pw)
        pass_ok = false
        if pw.count("0-9") > 0 && pw.count("a-z") > 0 && pw.length > 5
            pass_ok = true
        end
        return pass_ok
    end

    class Validator
        
        include Auth
        attr_reader :policies

        def find_group_policies(cred_id)
            policies = []
            Group.each do |group|
                group.group_memberships.each do |membership|
                    if membership.account_id == @ac_id
                        policies.push(group.group_policy)
                    end
                end
            end
            return policies
        end


        def initialize(cred_id,service_name,action,options)
            @cred_id = cred_id
            @service_name = service_name
            @action = action
            @options = options
            @account = Auth.find_account(cred_id)
            @ac_id = @account.id
            @policies = self.find_group_policies(cred_id)
            @provider = Account.find_cloud_credential(cred_id).cloud_provider
            @governance = nil
            @monitor = nil
            if !options.nil?
                @resource_id = options[:resource_id]
                @params = options[:params]
                if !@params.nil?
                    if !@params[:region].nil?
                        @region = @params[:region]
                    end
                    if !@params["cred_id"].nil?
                        @cloud_cred = Account.find_cloud_credential(@params["cred_id"])
                        @options_account = Auth.find_account(@params["cred_id"])
                    end
                end
            end
        end

        #List of Actions
        def validatePolicy(policy)
            if !policy.nil?
                #find which provider is being used.
                self.findProvider(policy)
                #Determine which action is being taken.
                case @action
                when "action"
                    return self.canUseService()
                when "create_instance"
                    return self.canCreateInstance('max_on_demand')
                when "create_rds"
                    return self.canCreateInstance('max_rds')
                when "create_spot"
                    return self.canCreateInstance('max_spot')
                when "create_reserved"
                    return self.canCreateInstance('max_reserved')
                when "create_autoscale"
                    return self.canCreateInstance('max_in_autoscale')
                when "create_default_alarms"
                    return self.createAlarms()
                when "create_auto_tags"
                    return self.createTags(policy)
                when "create_vpc_instance"
                    return self.createVpcInstance()
                when "modify_gateway"
                    return self.canModifyGateway('vpc_rules')
                end

            end
            return true
        end
        
        #Check which cloud provider is being used
        def findProvider(policy)
            if( @provider === "OpenStack" )
                @governance = policy.os_governance
            elsif (@provider === "AWS")
                @governance = policy.aws_governance
            end
        end

        #Enabled Services
        def canUseService()
            enabled_services = @governance['enabled_services']
            return true if @account.permissions.length > 0
            if enabled_services.nil?
                return false
            elsif enabled_services.is_a? String
                if enabled_services == @service_name
                    return true
                end
            elsif enabled_services.is_a? Array
                enabled_services.each do |service|
                    if service == @service_name
                        return true
                    end
                end
            end
            return false
        end
        
        #User instace count
        def userIntanceCount()
            resources = @options[:resources]
            id = @options[:uid]
            option_count = @options[:instance_count]
            user_instance_count = 0
            user_info = ""
            if(!option_count.nil?)
                    if(option_count > 0)
                        user_instance_count = option_count
                    end                    
            else       
                resources.each do |resource|
                    if(@provider === "OpenStack")
                        user_info = resource.user_id
                    elsif (@provider === "AWS")
                        user_info = resource.tags["value"]
                    end 
                    if(id === user_info)
                        user_instance_count += 1 
                    end
                end
            end 
            return user_instance_count      
        end


        #Max Instances
        def canCreateInstance(max)
            max_instance = @governance[max]
            user_instances = self.userIntanceCount()
            if max_instance == ""
                return true
            elsif user_instances >= max_instance.to_i
                return false
            else return true
            end
        end
        
        #Modify Gateways
        def canModifyGateway(rules)
            return false if !@governance[rules].include?(@options)
            return true
        end
        
        #default Alarms
        def createAlarms()
            namespace = @options[:namespace]
            alarms = @governance['default_alarms']
            @monitor = Fog::AWS::CloudWatch.new({:aws_access_key_id => @cloud_cred.access_key, :aws_secret_access_key => @cloud_cred.secret_key, :region => @region})
            alarms.each do |alarm|
                if alarm["namespace"] == namespace
                    self.newAlarm(alarm)
                end
            end
            
            return true
        end

        #createAlarms helper fuction
        def newAlarm(alarm)
            @monitor.alarms.create({"id"=>"SS_"+@resource_id+"_"+alarm['id']+Time.now.to_i.to_s,
                                    "dimensions"=> [{"Name" => alarm['dimensions'][0]['Name'],"Value" => @resource_id}],
                                    "metric_name"=> alarm['metric_name'],
                                    "threshold"=> alarm['threshold'],
                                    "namespace"=> alarm['namespace'],
                                    "comparison_operator"=> alarm['comparison_operator'],
                                    "statistic"=> "Average",
                                    "period"=> alarm['period'],
                                    "evaluation_periods"=> 1,
                                    "alarm_actions"=> alarm['alarm_actions'],
                                    "ok_actions"=> [],
                                    "insufficient_data_actions"=> []})
        end


        #create tags
        def createTags(policy)
            tags = @governance['auto_tags']
            @compute = Fog::Compute::AWS.new({:aws_access_key_id => @cloud_cred.access_key, :aws_secret_access_key => @cloud_cred.secret_key, :region => @region})
            
            if tags.include?("ProjectName")
                @compute.tags.create(:resource_id => @resource_id, :key => "ProjectName", :value => @governance['project_name'])
            end
            if tags.include?("UserName")
                @compute.tags.create(:resource_id => @resource_id, :key => "UserName", :value => @options_account['login'])
            end
            if tags.include?("GroupName")
                @compute.tags.create(:resource_id => @resource_id, :key => "GroupName", :value => policy.name)
            end
            if tags.include?("Modifiable")
                @compute.tags.create(:resource_id => @resource_id, :key => "Modifiable", :value => 'Modifiable')
            end
            
            return true
        end
        
        def createVpcInstance()
            vpc_rules = @governance['vpc_rules']
            if !vpc_rules.nil?
                instance = @options[:instance]
                cred_id = @params[:cred_id]
                @compute = Fog::Compute::AWS.new({:aws_access_key_id => @cloud_cred.access_key, :aws_secret_access_key => @cloud_cred.secret_key, :region => @region})
                if vpc_rules.include?("require_vpc")
                    instance['subnet_id'] = @governance['default_subnet']
                    response = @compute.servers.create(instance)
                    Auth.validate(cred_id,"Elastic Compute Cloud","create_default_alarms",{:params => @params, :resource_id => response.id, :namespace => "AWS/EC2"})
                    Auth.validate(cred_id,"Elastic Compute Cloud","create_auto_tags",{:params => @params, :resource_id => response.id})
                    return false
                end
            end
            return true
        end
    end
end
