require 'mina/bundler'
require 'mina/rails'
require 'mina/git'
require 'mina/rbenv'
require 'mina/slack/tasks'

set :repository, 'git@github.com:peatio/peatio_beijing.git'
set :user, 'deploy'
set :deploy_to, '/home/deploy/peatio'

branch = ENV['branch'] || 'production'
case ENV['to']
when 'demo'
  set :domain, 'demo.peat.io'
when 'peatio-daemon'
  set :domain, 'peatio-daemon'
when 'peatio-redis'
  set :domain, 'peatio-redis'
when 'peatio-admin'
  set :domain, 'peatio-admin'
when 'yunbi-web-01'
  set :domain, 'yunbi-web-01'
else
  branch = 'staging'
  set :domain, 'peatio-stg'
end

set :branch, branch

set :shared_paths, [
  'config/database.yml',
  'config/application.yml',
  'config/currencies.yml',
  'config/markets.yml',
  'config/amqp.yml',
  'config/banks.yml',
  'config/deposit_channels.yml',
  'config/withdraw_channels.yml',
  'public/uploads',
  'tmp',
  'log'
]

task :environment do
  invoke :'rbenv:load'
end

task setup: :environment do
  queue! %[mkdir -p "#{deploy_to}/shared/log"]
  queue! %[chmod g+rx,u+rwx "#{deploy_to}/shared/log"]

  queue! %[mkdir -p "#{deploy_to}/shared/config"]
  queue! %[chmod g+rx,u+rwx "#{deploy_to}/shared/config"]

  queue! %[mkdir -p "#{deploy_to}/shared/tmp"]
  queue! %[chmod g+rx,u+rwx "#{deploy_to}/shared/tmp"]

  queue! %[mkdir -p "#{deploy_to}/shared/public/uploads"]
  queue! %[chmod g+rx,u+rwx "#{deploy_to}/shared/public/uploads"]

  queue! %[touch "#{deploy_to}/shared/config/database.yml"]
  queue! %[touch "#{deploy_to}/shared/config/currencies.yml"]
  queue! %[touch "#{deploy_to}/shared/config/application.yml"]
  queue! %[touch "#{deploy_to}/shared/config/markets.yml"]
  queue! %[touch "#{deploy_to}/shared/config/amqp.yml"]
  queue! %[touch "#{deploy_to}/shared/config/banks.yml"]
  queue! %[touch "#{deploy_to}/shared/config/deposit_channels.yml"]
  queue! %[touch "#{deploy_to}/shared/config/withdraw_channels.yml"]
end

desc "Deploys the current version to the server."
task deploy: :environment do
  deploy do
    invoke :'git:clone'
    invoke :'deploy:link_shared_paths'
    invoke :'bundle:install'
    invoke :'rails:db_migrate'
    invoke :'rails:assets_precompile'

    to :launch do
      invoke :del_admin
      invoke :del_daemons
      invoke :'passenger:restart'
    end
  end
end

namespace :passenger do
  desc "Restart Passenger"
  task :restart do
    queue %{
      echo "-----> Restarting passenger"
      cd #{deploy_to}/current
      #{echo_cmd %[mkdir -p tmp]}
      #{echo_cmd %[touch tmp/restart.txt]}
    }
  end
end

namespace :daemons do
  desc "Start Daemons"
  task start: :environment do
    queue %{
      cd #{deploy_to}/current
      RAILS_ENV=production bundle exec ./bin/rake daemons:start
      echo Daemons START DONE!!!
    }
  end

  desc "Stop Daemons"
  task stop: :environment do
    queue %{
      cd #{deploy_to}/current
      RAILS_ENV=production bundle exec ./bin/rake daemons:stop
      echo Daemons STOP DONE!!!
    }
  end

  desc "Query Daemons"
  task status: :environment do
    queue %{
      cd #{deploy_to}/current
      RAILS_ENV=production bundle exec ./bin/rake daemons:status
    }
  end
end

desc "Generate liability proof"
task 'solvency:liability_proof' do
  queue "cd #{deploy_to}/current && RAILS_ENV=production bundle exec rake solvency:liability_proof"
end

desc 'delete admin'
task :del_admin do
  if ['yunbi-web-01'].include?(domain)
    queue! "rm -rf #{deploy_to}/current/app/controllers/admin"
    queue! "rm -rf #{deploy_to}/current/app/views/admin"
    queue! "rm -rf #{deploy_to}/current/app/models/worker"

    queue! "sed -i '/draw\ :admin/d' #{deploy_to}/current/config/routes.rb"
  end
end

def remove_daemons(daemons)
  daemons.each {|d| queue! "rm -rf #{deploy_to}/current/lib/daemons/#{d}" }
end

def remove_except(daemons)
  unless daemons.empty?
    Dir[File.dirname(__FILE__)+'/../lib/daemons/*'].each do |path|
      filename = File.basename(path)
      if not daemons.include?(filename)
        queue! "rm -rf #{deploy_to}/current/lib/daemons/#{filename}"
      end
    end
  end
end

redis_daemons = ['k.rb', 'k_ctl', 'stats.rb', 'stats_ctl', 'slack_ctl', 'amqp_daemon.rb']

desc 'delete daemons'
task :del_daemons do
  case domain
  when 'peatio-admin'
    queue! "rm -rf #{deploy_to}/current/lib/daemons"
  when 'peatio-daemon'
    remove_daemons redis_daemons
  when 'yunbi-web-01'
    queue! "rm -rf #{deploy_to}/current/lib/daemons"
  when 'peatio-redis'
    remove_except redis_daemons
  when 'peatio-stg'
    remove_daemons %w(stats.rb stats_ctl slack_ctl)
  end
end
