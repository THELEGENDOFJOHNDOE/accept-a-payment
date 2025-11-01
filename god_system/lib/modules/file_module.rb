# frozen_string_literal: true

require 'fileutils'

module GodSystem
  module Modules
    class FileModule
      def self.copy(source, destination)
        FileUtils.cp(source, destination)
        { success: true, message: "Copied #{source} to #{destination}" }
      rescue => e
        { success: false, error: e.message }
      end

      def self.move(source, destination)
        FileUtils.mv(source, destination)
        { success: true, message: "Moved #{source} to #{destination}" }
      rescue => e
        { success: false, error: e.message }
      end

      def self.rename(old_name, new_name)
        File.rename(old_name, new_name)
        { success: true, message: "Renamed #{old_name} to #{new_name}" }
      rescue => e
        { success: false, error: e.message }
      end

      def self.chmod(path, mode)
        FileUtils.chmod(mode, path)
        { success: true, message: "Changed permissions of #{path} to #{mode}" }
      rescue => e
        { success: false, error: e.message }
      end

      def self.file_info(path)
        stat = File.stat(path)
        info = {
          size: stat.size,
          created: stat.ctime,
          modified: stat.mtime,
          permissions: stat.mode.to_s(8),
          directory: stat.directory?,
          file: stat.file?
        }
        { success: true, result: info }
      rescue => e
        { success: false, error: e.message }
      end
    end
  end
end
