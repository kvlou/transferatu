module Transferatu
  class WorkerStatus < Sequel::Model
    plugin :timestamps

    many_to_one :transfer

    def_dataset_method(:check) do |*names|
      self.order(:dyno_name, Sequel.desc(:created_at)).distinct(:dyno_name).where(dyno_name: names)
    end

    def before_create
      if dyno_name.nil?
        self.dyno_name = ENV['DYNO']
      end
      if uuid.nil?
        # Dyno hostnames in private spaces have prefix "dyno-"
        self.uuid = Socket.gethostname
        self.uuid.slice! "dyno-" if uuid.start_with? "dyno-"
      end
      if host.nil?
        self.host = File.readlines('/etc/hosts').find do |line|
          line.chomp.end_with? uuid
        end.split(' ').first
      end
    end
  end
end
