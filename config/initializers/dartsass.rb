# Required because dartsass was only building application.scss by default
Rails.application.config.dartsass.builds = {
  "." => "."
}

# In development, emit expanded (multi-line) CSS so browser DevTools source
# maps resolve edits to the correct SCSS rule. With the default compressed
# output all rules sit on one line, which makes DevTools misattribute live
# edits to nearby selectors or the wrong media query.
if Rails.env.development?
  Rails.application.config.dartsass.build_options = [ "--style=expanded", "--embed-sources" ]
end
