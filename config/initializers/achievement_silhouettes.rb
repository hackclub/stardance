# frozen_string_literal: true

module AchievementSilhouettes
  SALT = "stardance-achievements-secret"

  def self.source_dirs
    dirs = [ Rails.root.join("app/assets/images/achievements") ]
    secret_dir = Rails.root.join("secrets/assets/images/achievements")
    dirs << secret_dir if secret_dir.exist?
    dirs
  end

  def self.hashed_name(filename)
    ext = File.extname(filename)
    base = File.basename(filename, ext)
    hash = Digest::SHA1.hexdigest("#{SALT}:#{base}")[0, 16]
    "#{hash}#{ext}"
  end

  def self.silhouette_path(icon_name)
    %w[png svg jpg jpeg gif webp].each do |ext|
      filename = "#{icon_name}.#{ext}"
      hashed = hashed_name(filename)

      # Check app/assets path
      app_silhouette = "achievements/silhouettes/#{hashed}"
      if asset_exists?(app_silhouette) || source_file_exists?(Rails.root.join("app/assets/images/achievements", filename))
        return app_silhouette
      end

      # Check secrets path
      secrets_silhouette = "achievements/silhouettes/#{hashed}"
      if source_file_exists?(Rails.root.join("secrets/assets/images/achievements", filename))
        return secrets_silhouette
      end
    end

    nil
  end

  def self.asset_exists?(path)
    return false unless Rails.application.assets

    Rails.application.assets.load_path.find(path).present?
  end

  def self.source_file_exists?(path)
    path.exist?
  end

  def self.generate!
    source_dirs.each do |source_dir|
      next unless source_dir.exist?

      silhouette_dir = source_dir.join("silhouettes")
      FileUtils.mkdir_p(silhouette_dir)

      Dir.glob(source_dir.join("*.{png,jpg,jpeg,gif,webp}")).each do |file|
        filename = File.basename(file)
        hashed_filename = hashed_name(filename)
        output_path = silhouette_dir.join(hashed_filename)

        next if output_path.exist? && File.mtime(output_path) >= File.mtime(file)

        require "mini_magick"

        begin
          image = MiniMagick::Image.open(file)
          image.combine_options do |c|
            c.alpha "extract"
            c.background "black"
            c.alpha "shape"
          end
          image.write(output_path)

          Rails.logger.info "[Achievements] Generated silhouette: #{filename} -> #{hashed_filename}"
        rescue MiniMagick::Error => e
          Rails.logger.warn "[Achievements] Skipping silhouette generation: #{e.message}"
          return
        end
      end

      Dir.glob(source_dir.join("*.svg")).each do |file|
        filename = File.basename(file)
        hashed_filename = hashed_name(filename)
        output_path = silhouette_dir.join(hashed_filename)

        next if output_path.exist? && File.mtime(output_path) >= File.mtime(file)

        svg_content = File.read(file)
        silhouette_svg = svg_content
          .gsub(/fill="[^"]*"/, 'fill="black"')
          .gsub(/fill='[^']*'/, "fill='black'")
          .gsub(/stroke="[^"]*"/, 'stroke="black"')
          .gsub(/stroke='[^']*'/, "stroke='black'")

        silhouette_svg = silhouette_svg.gsub(/<svg/, '<svg fill="black"') if silhouette_svg !~ /fill=/

        File.write(output_path, silhouette_svg)

        Rails.logger.info "[Achievements] Generated silhouette: #{filename} -> #{hashed_filename}"
      end
    end
  end
end

Rails.application.config.after_initialize do
  next unless Rails.env.development?

  AchievementSilhouettes.generate!
end
