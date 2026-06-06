Gem::Specification.new do |spec|
  spec.name = "raffle"
  spec.version = "0.1.0"
  spec.summary = "We're raffling GPUs today!"
  spec.authors = [ "Hack Club" ]

  spec.add_dependency "rails", ">= 8.1"
  spec.add_dependency "omniauth-github", "~> 2.0"
end
