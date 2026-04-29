class KitchenHelpCardsComponent < ApplicationComponent
  def view_template
    div(class: "kitchen-help__content") do
      h2(class: "kitchen-help__title") { "Need any help?" }
      div(class: "kitchen-help__grid") do
        div(class: "state-card state-card--neutral kitchen-help-card") do
          div(class: "state-card__status-pill") do
            div(class: "state-card__icon-circle") do
              inline_svg_tag("icons/info.svg", alt: "")
            end
          end
          div(class: "state-card__title") { "View the FAQ" }
          div(class: "state-card__description") do
            "The FAQ (on Slack) answers most questions about Stardance! Give it a read to find out more about how Stardance works."
          end
          div(class: "state-card__cta") do
            a(href: "https://hackclub.slack.com/app_redirect?channel=C09MATKQM8C", class: "btn btn--borderless btn--bg_yellow", target: "_blank") do
              span { "Go to Stardance FAQ" }
            end
          end
        end

        div(class: "state-card state-card--neutral kitchen-help-card") do
          div(class: "state-card__status-pill") do
            div(class: "state-card__icon-circle") do
              inline_svg_tag("icons/help.svg", alt: "")
            end
          end
          div(class: "state-card__title") { "Help channel on Slack" }
          div(class: "state-card__description") do
            "Still stuck after reading the FAQ? Ask our community in the #stardance-help channel."
          end
          div(class: "state-card__cta") do
            a(href: "https://hackclub.slack.com/app_redirect?channel=C09MATKQM8C", class: "btn btn--borderless btn--bg_yellow", target: "_blank") do
              span { "Go to #stardance-help" }
            end
          end
        end
      end
      p(class: "kitchen-help__paragraph") do
        plain "If you're unable to use Slack, you can also send an e-mail to "
        a(href: "mailto:stardance@hackclub.com") { "stardance@hackclub.com" }
        plain "."
      end
    end
  end
end
