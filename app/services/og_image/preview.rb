module OgImage
  module Preview
    VIEW_CLASSES = [
      OgImage::Home,
      OgImage::Project,
      OgImage::User,
      OgImage::Devlog,
      OgImage::Missions,
      OgImage::Shop
    ].freeze

    class << self
      def all
        VIEW_CLASSES.flat_map do |klass|
          klass::PREVIEWS.keys.map { |key| "#{klass.name.demodulize.underscore}/#{key}" }
        end
      end

      def for(name)
        class_name, variant = name.to_s.split("/", 2)
        variant ||= "default"

        klass = VIEW_CLASSES.find { |k| k.name.demodulize.underscore == class_name }
        return nil unless klass

        klass::PREVIEWS[variant]&.call
      end

      def meta_for(name)
        class_name, variant = name.to_s.split("/", 2)
        variant ||= "default"

        klass = VIEW_CLASSES.find { |k| k.name.demodulize.underscore == class_name }
        return nil unless klass
        return nil unless klass.const_defined?(:PREVIEW_META)

        klass::PREVIEW_META[variant]
      end
    end
  end
end
