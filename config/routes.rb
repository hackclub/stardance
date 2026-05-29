# == Route Map
#
# Routes for application:
#                                     Prefix Verb   URI Pattern                                                                                       Controller#Action
#                                    sitemap GET    /sitemap.xml(.:format)                                                                            sitemaps#index {format: :xml}
#                                   og_image GET    /og/:page(.:format)                                                                               og_images#show {format: :png}
#                                       root GET    /                                                                                                 landing#index
#                             user_ref_rsvps PATCH  /rsvps/user_ref(.:format)                                                                         rsvps#user_ref
#                                      rsvps POST   /rsvps(.:format)                                                                                  rsvps#create
#                               confirm_rsvp GET    /rsvps/confirm/:token(.:format)                                                                   rsvps#confirm
#                                    tic_tac GET    /tic_tac(.:format)                                                                                rsvps#tic_tac {format: :text}
#                                       shop GET    /shop(.:format)                                                                                   shop#index
#                             shop_my_orders GET    /shop/my_orders(.:format)                                                                         shop#my_orders
#                          cancel_shop_order DELETE /shop/cancel_order/:order_id(.:format)                                                            shop#cancel_order
#                                 shop_order GET    /shop/order(.:format)                                                                             shop#order
#                                            POST   /shop/order(.:format)                                                                             shop#create_order
#                         shop_update_region PATCH  /shop/update_region(.:format)                                                                     shop#update_region
#                              shop_category GET    /shop/category/:slug(.:format)                                                                    shop#category
#                           shop_suggestions POST   /shop_suggestions(.:format)                                                                       shop_suggestions#create
#                        review_report_token GET    /report-reviews/review/:token(.:format)                                                           report_reviews#review
#                       dismiss_report_token GET    /report-reviews/dismiss/:token(.:format)                                                          report_reviews#dismiss
#                                   new_rate GET    /rate/new(.:format)                                                                               votes#new
#                                      votes POST   /votes(.:format)                                                                                  votes#create
#                                   new_vote GET    /votes/new(.:format)                                                                              votes#new
#                                 votes_skip POST   /votes/skip(.:format)                                                                             votes/skips#create
#                         rails_health_check GET    /up(.:format)                                                                                     rails/health#show
#                                 test_error GET    /test_error(.:format)                                                                             debug#error
#                          letter_opener_web        /letter_opener                                                                                    LetterOpenerWeb::Engine
#                          og_image_previews GET    /og_image_previews(.:format)                                                                      og_image_previews#index
#                           og_image_preview GET    /og_image_previews/*id(.:format)                                                                  og_image_previews#show
#                             action_mailbox        /rails/action_mailbox                                                                             ActionMailbox::Engine
#                            active_insights        /insights                                                                                         ActiveInsights::Engine
#                    auth_hackatime_callback GET    /auth/hackatime/callback(.:format)                                                                identities#hackatime
#                                            GET    /auth/:provider/callback(.:format)                                                                sessions#create
#                               auth_failure GET    /auth/failure(.:format)                                                                           sessions#failure
#                                     logout DELETE /logout(.:format)                                                                                 sessions#destroy
#                             dev_login_auto GET    /dev_login(.:format)                                                                              sessions#dev_login
#                                  dev_login GET    /dev_login/:id(.:format)                                                                          sessions#dev_login
#                             oauth_callback GET    /oauth/callback(.:format)                                                                         sessions#create
#                                       home GET    /home(.:format)                                                                                   home#index
#                                leaderboard GET    /leaderboard(.:format)                                                                            leaderboard#index
#                                     events GET    /events(.:format)                                                                                 events#index
#                                 my_balance GET    /my/balance(.:format)                                                                             my/balances#show
#                  streamer_mode_my_settings POST   /my/settings/streamer_mode(.:format)                                                              my/settings#toggle_streamer_mode
#                                my_settings PATCH  /my/settings(.:format)                                                                            my/settings#update
#                                            PUT    /my/settings(.:format)                                                                            my/settings#update
#                              my_dismissals POST   /my/dismissals(.:format)                                                                          my/dismissals#create
#                    my_verification_refresh POST   /my/verification/refresh(.:format)                                                                my/verifications#refresh
#                         my_pretend_idv_dev POST   /my/dev/pretend_idv(.:format)                                                                     my/dev_tools#pretend_idv
#                            my_achievements GET    /my/achievements(.:format)                                                                        achievements#index
#                reveal_address_seller_order POST   /seller/orders/:id/reveal_address(.:format)                                                       seller/orders#reveal_address
#                mark_fulfilled_seller_order POST   /seller/orders/:id/mark_fulfilled(.:format)                                                       seller/orders#mark_fulfilled
#                              seller_orders GET    /seller/orders(.:format)                                                                          seller/orders#index
#                               seller_order GET    /seller/orders/:id(.:format)                                                                      seller/orders#show
#                           onboarding_start POST   /onboarding/start(.:format)                                                                       onboarding/wizard#start
#                         onboarding_welcome GET    /onboarding/welcome(.:format)                                                                     onboarding/wizard#welcome
#                        onboarding_birthday GET    /onboarding/birthday(.:format)                                                                    onboarding/wizard#birthday
#                                            POST   /onboarding/birthday(.:format)                                                                    onboarding/wizard#submit_birthday
#                        onboarding_age_gate GET    /onboarding/age_gate(.:format)                                                                    onboarding/wizard#age_gate
#                      onboarding_experience GET    /onboarding/experience(.:format)                                                                  onboarding/wizard#experience
#                                            POST   /onboarding/experience(.:format)                                                                  onboarding/wizard#submit_experience
#               onboarding_experience_result GET    /onboarding/experience_result(.:format)                                                           onboarding/wizard#experience_result
#                       onboarding_interests GET    /onboarding/interests(.:format)                                                                   onboarding/wizard#interests
#                                            POST   /onboarding/interests(.:format)                                                                   onboarding/wizard#submit_interests
#                onboarding_interests_result GET    /onboarding/interests_result(.:format)                                                            onboarding/wizard#interests_result
#                            onboarding_name GET    /onboarding/name(.:format)                                                                        onboarding/wizard#name
#                                            POST   /onboarding/name(.:format)                                                                        onboarding/wizard#submit_name
#                                 admin_root GET    /admin(.:format)                                                                                  admin/application#index
#                               admin_blazer        /admin/blazer                                                                                     Blazer::Engine
#                                                   /admin/flipper                                                                                    Flipper::UI
#                 admin_mission_control_jobs        /admin/jobs                                                                                       MissionControl::Jobs::Engine
#                           admin_user_roles POST   /admin/users/:user_id/roles(.:format)                                                             admin/users/roles#create
#                            admin_user_role DELETE /admin/users/:user_id/roles/:name(.:format)                                                       admin/users/roles#destroy
#                             admin_user_ban DELETE /admin/users/:user_id/ban(.:format)                                                               admin/users/bans#destroy
#                                            POST   /admin/users/:user_id/ban(.:format)                                                               admin/users/bans#create
#                   admin_user_impersonation POST   /admin/users/:user_id/impersonation(.:format)                                                     admin/users/impersonations#create
#                   admin_user_feature_flags POST   /admin/users/:user_id/feature_flags(.:format)                                                     admin/users/feature_flags#create
#                    admin_user_feature_flag DELETE /admin/users/:user_id/feature_flags/:feature(.:format)                                            admin/users/feature_flags#destroy
#                  admin_user_hackatime_sync POST   /admin/users/:user_id/hackatime_sync(.:format)                                                    admin/users/hackatime_syncs#create
#                 admin_user_order_rejection POST   /admin/users/:user_id/order_rejection(.:format)                                                   admin/users/order_rejections#create
#             admin_user_balance_adjustments POST   /admin/users/:user_id/balance_adjustments(.:format)                                               admin/users/balance_adjustments#create
#              admin_user_grant_cancellation POST   /admin/users/:user_id/grant_cancellation(.:format)                                                admin/users/grant_cancellations#create
#                    admin_user_verification POST   /admin/users/:user_id/verification(.:format)                                                      admin/users/verifications#create
#                    admin_user_vote_balance PATCH  /admin/users/:user_id/vote_balance(.:format)                                                      admin/users/vote_balances#update
#                                            PUT    /admin/users/:user_id/vote_balance(.:format)                                                      admin/users/vote_balances#update
#                   admin_user_ysws_override PATCH  /admin/users/:user_id/ysws_override(.:format)                                                     admin/users/ysws_overrides#update
#                                            PUT    /admin/users/:user_id/ysws_override(.:format)                                                     admin/users/ysws_overrides#update
#                           admin_user_votes GET    /admin/users/:user_id/votes(.:format)                                                             admin/users/votes#index
#                                admin_users GET    /admin/users(.:format)                                                                            admin/users#index
#                                 admin_user GET    /admin/users/:id(.:format)                                                                        admin/users#show
#                                            PATCH  /admin/users/:id(.:format)                                                                        admin/users#update
#                                            PUT    /admin/users/:id(.:format)                                                                        admin/users#update
#                        admin_impersonation DELETE /admin/impersonation(.:format)                                                                    admin/users/impersonations#destroy
#                      restore_admin_project POST   /admin/projects/:id/restore(.:format)                                                             admin/projects#restore
#                       delete_admin_project POST   /admin/projects/:id/delete(.:format)                                                              admin/projects#delete
#           update_ship_status_admin_project POST   /admin/projects/:id/update_ship_status(.:format)                                                  admin/projects#update_ship_status
#                  force_state_admin_project POST   /admin/projects/:id/force_state(.:format)                                                         admin/projects#force_state
#                        votes_admin_project GET    /admin/projects/:id/votes(.:format)                                                               admin/projects#votes
#                             admin_projects GET    /admin/projects(.:format)                                                                         admin/projects#index
#                              admin_project GET    /admin/projects/:id(.:format)                                                                     admin/projects#show
#                           admin_user_perms GET    /admin/user-perms(.:format)                                                                       admin/users#user_perms
#                              admin_support GET    /admin/support(.:format)                                                                          admin/support/dashboards#show
#                                admin_fraud GET    /admin/fraud(.:format)                                                                            admin/fraud/dashboards#show
#                                 admin_shop GET    /admin/shop(.:format)                                                                             admin/shop/dashboard#show
#                 admin_clear_carousel_cache POST   /admin/shop/clear-carousel-cache(.:format)                                                        admin/shop/dashboard#clear_carousel_cache
#          preview_markdown_admin_shop_items POST   /admin/shop/items/preview_markdown(.:format)                                                      admin/shop/items#preview_markdown
#           request_approval_admin_shop_item POST   /admin/shop/items/:id/request_approval(.:format)                                                  admin/shop/items#request_approval
#                           admin_shop_items POST   /admin/shop/items(.:format)                                                                       admin/shop/items#create
#                        new_admin_shop_item GET    /admin/shop/items/new(.:format)                                                                   admin/shop/items#new
#                       edit_admin_shop_item GET    /admin/shop/items/:id/edit(.:format)                                                              admin/shop/items#edit
#                            admin_shop_item GET    /admin/shop/items/:id(.:format)                                                                   admin/shop/items#show
#                                            PATCH  /admin/shop/items/:id(.:format)                                                                   admin/shop/items#update
#                                            PUT    /admin/shop/items/:id(.:format)                                                                   admin/shop/items#update
#                                            DELETE /admin/shop/items/:id(.:format)                                                                   admin/shop/items#destroy
#            reveal_address_admin_shop_order POST   /admin/shop/orders/:id/reveal_address(.:format)                                                   admin/shop/orders#reveal_address
#              reveal_phone_admin_shop_order POST   /admin/shop/orders/:id/reveal_phone(.:format)                                                     admin/shop/orders#reveal_phone
#                   approve_admin_shop_order POST   /admin/shop/orders/:id/approve(.:format)                                                          admin/shop/orders#approve
#              review_order_admin_shop_order POST   /admin/shop/orders/:id/review_order(.:format)                                                     admin/shop/orders#review_order
#                    reject_admin_shop_order POST   /admin/shop/orders/:id/reject(.:format)                                                           admin/shop/orders#reject
#             place_on_hold_admin_shop_order POST   /admin/shop/orders/:id/place_on_hold(.:format)                                                    admin/shop/orders#place_on_hold
#         release_from_hold_admin_shop_order POST   /admin/shop/orders/:id/release_from_hold(.:format)                                                admin/shop/orders#release_from_hold
#            mark_fulfilled_admin_shop_order POST   /admin/shop/orders/:id/mark_fulfilled(.:format)                                                   admin/shop/orders#mark_fulfilled
#     update_internal_notes_admin_shop_order POST   /admin/shop/orders/:id/update_internal_notes(.:format)                                            admin/shop/orders#update_internal_notes
#               assign_user_admin_shop_order POST   /admin/shop/orders/:id/assign_user(.:format)                                                      admin/shop/orders#assign_user
#          cancel_hcb_grant_admin_shop_order POST   /admin/shop/orders/:id/cancel_hcb_grant(.:format)                                                 admin/shop/orders#cancel_hcb_grant
#      refresh_verification_admin_shop_order POST   /admin/shop/orders/:id/refresh_verification(.:format)                                             admin/shop/orders#refresh_verification
#           send_to_theseus_admin_shop_order POST   /admin/shop/orders/:id/send_to_theseus(.:format)                                                  admin/shop/orders#send_to_theseus
# approve_verification_call_admin_shop_order POST   /admin/shop/orders/:id/approve_verification_call(.:format)                                        admin/shop/orders#approve_verification_call
#               force_state_admin_shop_order POST   /admin/shop/orders/:id/force_state(.:format)                                                      admin/shop/orders#force_state
#                          admin_shop_orders GET    /admin/shop/orders(.:format)                                                                      admin/shop/orders#index
#                           admin_shop_order GET    /admin/shop/orders/:id(.:format)                                                                  admin/shop/orders#show
#              dismiss_admin_shop_suggestion POST   /admin/shop/suggestions/:id/dismiss(.:format)                                                     admin/shop/suggestions#dismiss
#     disable_for_user_admin_shop_suggestion POST   /admin/shop/suggestions/:id/disable_for_user(.:format)                                            admin/shop/suggestions#disable_for_user
#                     admin_shop_suggestions GET    /admin/shop/suggestions(.:format)                                                                 admin/shop/suggestions#index
#                             admin_messages GET    /admin/messages(.:format)                                                                         admin/messages#index
#                                            POST   /admin/messages(.:format)                                                                         admin/messages#create
#                        admin_support_vibes GET    /admin/support_vibes(.:format)                                                                    admin/support_vibes#index
#                                            POST   /admin/support_vibes(.:format)                                                                    admin/support_vibes#create
#                             admin_sw_vibes GET    /admin/sw_vibes(.:format)                                                                         admin/sw_vibes#index
#                     admin_suspicious_votes GET    /admin/suspicious_votes(.:format)                                                                 admin/suspicious_votes#index
#                           admin_audit_logs GET    /admin/audit_logs(.:format)                                                                       admin/audit_logs#index
#                            admin_audit_log GET    /admin/audit_logs/:id(.:format)                                                                   admin/audit_logs#show
#          process_demo_broken_admin_reports POST   /admin/reports/process_demo_broken(.:format)                                                      admin/reports#process_demo_broken
#                        review_admin_report POST   /admin/reports/:id/review(.:format)                                                               admin/reports#review
#                       dismiss_admin_report POST   /admin/reports/:id/dismiss(.:format)                                                              admin/reports#dismiss
#                              admin_reports GET    /admin/reports(.:format)                                                                          admin/reports#index
#                               admin_report GET    /admin/reports/:id(.:format)                                                                      admin/reports#show
#           approve_admin_fulfillment_payout POST   /admin/fulfillment_payouts/:id/approve(.:format)                                                  admin/fulfillment_payouts#approve
#            reject_admin_fulfillment_payout POST   /admin/fulfillment_payouts/:id/reject(.:format)                                                   admin/fulfillment_payouts#reject
#          trigger_admin_fulfillment_payouts POST   /admin/fulfillment_payouts/trigger(.:format)                                                      admin/fulfillment_payouts#trigger
#                  admin_fulfillment_payouts GET    /admin/fulfillment_payouts(.:format)                                                              admin/fulfillment_payouts#index
#                   admin_fulfillment_payout GET    /admin/fulfillment_payouts/:id(.:format)                                                          admin/fulfillment_payouts#show
#                      restore_admin_mission POST   /admin/missions/:slug/restore(.:format)                                                           admin/missions#restore
#                  admin_mission_guide_paste POST   /admin/missions/:mission_slug/guide_paste(.:format)                                               admin/missions/guide_pastes#create
#                admin_mission_guide_preview POST   /admin/missions/:mission_slug/guide_preview(.:format)                                             admin/missions/guide_previews#create
#                  admin_mission_memberships POST   /admin/missions/:mission_slug/memberships(.:format)                                               admin/missions/memberships#create
#                   admin_mission_membership PATCH  /admin/missions/:mission_slug/memberships/:id(.:format)                                           admin/missions/memberships#update
#                                            PUT    /admin/missions/:mission_slug/memberships/:id(.:format)                                           admin/missions/memberships#update
#                                            DELETE /admin/missions/:mission_slug/memberships/:id(.:format)                                           admin/missions/memberships#destroy
#                        admin_mission_steps POST   /admin/missions/:mission_slug/steps(.:format)                                                     admin/missions/steps#create
#                         admin_mission_step PATCH  /admin/missions/:mission_slug/steps/:id(.:format)                                                 admin/missions/steps#update
#                                            PUT    /admin/missions/:mission_slug/steps/:id(.:format)                                                 admin/missions/steps#update
#                                            DELETE /admin/missions/:mission_slug/steps/:id(.:format)                                                 admin/missions/steps#destroy
#                admin_mission_step_ordering POST   /admin/missions/:mission_slug/step_ordering(.:format)                                             admin/missions/step_orderings#create
#                       admin_mission_prizes POST   /admin/missions/:mission_slug/prizes(.:format)                                                    admin/missions/prizes#create
#                        admin_mission_prize PATCH  /admin/missions/:mission_slug/prizes/:id(.:format)                                                admin/missions/prizes#update
#                                            PUT    /admin/missions/:mission_slug/prizes/:id(.:format)                                                admin/missions/prizes#update
#                                            DELETE /admin/missions/:mission_slug/prizes/:id(.:format)                                                admin/missions/prizes#destroy
#                 admin_mission_shop_unlocks POST   /admin/missions/:mission_slug/shop_unlocks(.:format)                                              admin/missions/shop_unlocks#create
#                  admin_mission_shop_unlock DELETE /admin/missions/:mission_slug/shop_unlocks/:id(.:format)                                          admin/missions/shop_unlocks#destroy
#                             admin_missions GET    /admin/missions(.:format)                                                                         admin/missions#index
#                                            POST   /admin/missions(.:format)                                                                         admin/missions#create
#                          new_admin_mission GET    /admin/missions/new(.:format)                                                                     admin/missions#new
#                         edit_admin_mission GET    /admin/missions/:slug/edit(.:format)                                                              admin/missions#edit
#                              admin_mission GET    /admin/missions/:slug(.:format)                                                                   admin/missions#show
#                                            PATCH  /admin/missions/:slug(.:format)                                                                   admin/missions#update
#                                            PUT    /admin/missions/:slug(.:format)                                                                   admin/missions#update
#                                            DELETE /admin/missions/:slug(.:format)                                                                   admin/missions#destroy
#             next_admin_certification_ships GET    /admin/certification/ship_cert/next(.:format)                                                     admin/certification/ships#next
#             claim_admin_certification_ship POST   /admin/certification/ship_cert/:id/claim(.:format)                                                admin/certification/ships#claim
#                  admin_certification_ships GET    /admin/certification/ship_cert(.:format)                                                          admin/certification/ships#index
#                   admin_certification_ship GET    /admin/certification/ship_cert/:id(.:format)                                                      admin/certification/ships#show
#                                            PATCH  /admin/certification/ship_cert/:id(.:format)                                                      admin/certification/ships#update
#                                            PUT    /admin/certification/ship_cert/:id(.:format)                                                      admin/certification/ships#update
#          admin_certification_devlog_review PATCH  /admin/certification/devlog_reviews/:id(.:format)                                                 admin/certification/devlog_reviews#update
#                                            PUT    /admin/certification/devlog_reviews/:id(.:format)                                                 admin/certification/devlog_reviews#update
#           admin_certification_ysws_reviews GET    /admin/certification/review(.:format)                                                             admin/certification/ysws#index
#            admin_certification_ysws_review GET    /admin/certification/review/:id(.:format)                                                         admin/certification/ysws#show
#      admin_certification_ysws_report_fraud POST   /admin/certification/review/:id/report_fraud(.:format)                                            admin/certification/ysws#report_fraud
#                                      queue GET    /queue(.:format)                                                                                  queue#index
#                             projects_setup GET    /projects/setup(.:format)                                                                         projects/setup#idea
#                 projects_setup_submit_idea POST   /projects/setup/idea(.:format)                                                                    projects/setup#submit_idea
#                        projects_setup_name GET    /projects/setup/name(.:format)                                                                    projects/setup#name
#                 projects_setup_submit_name POST   /projects/setup/name(.:format)                                                                    projects/setup#submit_name
#                    projects_setup_missions GET    /projects/setup/missions(.:format)                                                                projects/setup#missions
#              projects_setup_submit_mission POST   /projects/setup/missions(.:format)                                                                projects/setup#submit_mission
#                projects_setup_link_account GET    /projects/setup/link_account(.:format)                                                            projects/setup#link_account
#                     projects_setup_welcome GET    /projects/setup/welcome(.:format)                                                                 projects/setup#welcome
#                      add_test_time_project POST   /projects/:id/add_test_time(.:format)                                                             projects#add_test_time
#                        project_memberships POST   /projects/:project_id/memberships(.:format)                                                       projects/memberships#create
#                                 membership DELETE /memberships/:id(.:format)                                                                        projects/memberships#destroy
#                    versions_project_devlog GET    /projects/:project_id/devlogs/:id/versions(.:format)                                              projects/devlogs#versions
#               preview_time_project_devlogs GET    /projects/:project_id/devlogs/preview_time(.:format)                                              projects/devlogs#preview_time
#                            project_devlogs POST   /projects/:project_id/devlogs(.:format)                                                           projects/devlogs#create
#                        edit_project_devlog GET    /projects/:project_id/devlogs/:id/edit(.:format)                                                  projects/devlogs#edit
#                             project_devlog PATCH  /projects/:project_id/devlogs/:id(.:format)                                                       projects/devlogs#update
#                                            PUT    /projects/:project_id/devlogs/:id(.:format)                                                       projects/devlogs#update
#                                            DELETE /projects/:project_id/devlogs/:id(.:format)                                                       projects/devlogs#destroy
#                            project_reports POST   /projects/:project_id/reports(.:format)                                                           projects/reports#create
#                           project_og_image GET    /projects/:project_id/og_image(.:format)                                                          projects/og_images#show {format: :png}
#                         info_project_ships GET    /projects/:project_id/ships/info(.:format)                                                        projects/ships#info
#                       review_project_ships GET    /projects/:project_id/ships/review(.:format)                                                      projects/ships#review_step
#                      compose_project_ships GET    /projects/:project_id/ships/compose(.:format)                                                     projects/ships#compose
#                       project_ships_review POST   /projects/:project_id/ships/review(.:format)                                                      projects/ships/reviews#create
#                          new_project_ships GET    /projects/:project_id/ships/new(.:format)                                                         projects/ships#new
#                              project_ships POST   /projects/:project_id/ships(.:format)                                                             projects/ships#create
#                            project_mission DELETE /projects/:project_id/mission(.:format)                                                           projects/missions#destroy
#                                            POST   /projects/:project_id/mission(.:format)                                                           projects/missions#create
#                              project_magic DELETE /projects/:project_id/magic(.:format)                                                             projects/magic#destroy
#                                            POST   /projects/:project_id/magic(.:format)                                                             projects/magic#create
#        project_mission_section_completions POST   /projects/:project_id/mission_section_completions(.:format)                                       projects/mission_section_completions#create
#                 mission_section_completion DELETE /mission_section_completions/:mission_step_id(.:format)                                           projects/mission_section_completions#destroy
#                             readme_project GET    /projects/:id/readme(.:format)                                                                    projects#readme
#                             follow_project POST   /projects/:id/follow(.:format)                                                                    projects#follow
#                           unfollow_project DELETE /projects/:id/unfollow(.:format)                                                                  projects#unfollow
#                                   projects POST   /projects(.:format)                                                                               projects#create
#                                new_project GET    /projects/new(.:format)                                                                           projects#new
#                               edit_project GET    /projects/:id/edit(.:format)                                                                      projects#edit
#                                    project GET    /projects/:id(.:format)                                                                           projects#show
#                                            PATCH  /projects/:id(.:format)                                                                           projects#update
#                                            PUT    /projects/:id(.:format)                                                                           projects#update
#                                            DELETE /projects/:id(.:format)                                                                           projects#destroy
#                                devlog_like DELETE /devlogs/:devlog_id/like(.:format)                                                                likes#destroy
#                                            POST   /devlogs/:devlog_id/like(.:format)                                                                likes#create
#                            devlog_comments POST   /devlogs/:devlog_id/comments(.:format)                                                            comments#create
#                             devlog_comment DELETE /devlogs/:devlog_id/comments/:id(.:format)                                                        comments#destroy
#                              user_og_image GET    /users/:user_id/og_image(.:format)                                                                users/og_images#show {format: :png}
#                                user_follow DELETE /users/:user_id/follow(.:format)                                                                  follows#destroy
#                                            POST   /users/:user_id/follow(.:format)                                                                  follows#create
#                               devlogs_user GET    /users/:id/devlogs(.:format)                                                                      users#show {tab: "devlogs"}
#                               replies_user GET    /users/:id/replies(.:format)                                                                      users#show {tab: "replies"}
#                              projects_user GET    /users/:id/projects(.:format)                                                                     users#show {tab: "projects"}
#                             followers_user GET    /users/:id/followers(.:format)                                                                    users#followers
#                             following_user GET    /users/:id/following(.:format)                                                                    users#following
#                                       user GET    /users/:id(.:format)                                                                              users#show
#                                            PATCH  /users/:id(.:format)                                                                              users#update
#                                            PUT    /users/:id(.:format)                                                                              users#update
#                      username_availability GET    /username_availability(.:format)                                                                  users/username_availabilities#show
#                               search_users GET    /search/users(.:format)                                                                           search#users
#                            search_projects GET    /search/projects(.:format)                                                                        search#projects
#                                        edu GET    /edu(.:format)                                                                                    landing#edu
#                                     guides GET    /guides(.:format)                                                                                 guides#index
#                                      guide GET    /guides/:id(.:format)                                                                             guides#show
#                           mission_og_image GET    /missions/:mission_slug/og_image(.:format)                                                        missions/og_images#show {format: :png}
#                              guide_mission GET    /missions/:slug/guide(.:format)                                                                   missions#guide
#                                   missions GET    /missions(.:format)                                                                               missions#index
#                                    mission GET    /missions/:slug(.:format)                                                                         missions#show
#                 approve_mission_submission POST   /mission_submissions/:id/approve(.:format)                                                        mission_submissions#approve
#                  reject_mission_submission POST   /mission_submissions/:id/reject(.:format)                                                         mission_submissions#reject
#                    undo_mission_submission POST   /mission_submissions/:id/undo(.:format)                                                           mission_submissions#undo
#                  redeem_mission_submission GET    /mission_submissions/:id/redeem(.:format)                                                         mission_submissions#redeem
#                        mission_submissions GET    /mission_submissions(.:format)                                                                    mission_submissions#index
#                         mission_submission GET    /mission_submissions/:id(.:format)                                                                mission_submissions#show
#                                                   /400(.:format)                                                                                    errors#bad_request
#                                                   /404(.:format)                                                                                    errors#not_found
#                                                   /406(.:format)                                                                                    errors#not_acceptable
#                                                   /422(.:format)                                                                                    errors#unprocessable_entity
#                                                   /500(.:format)                                                                                    errors#internal_server_error
#                                            GET    /:ref(.:format)                                                                                   landing#index {ref: /[a-z0-9][a-z0-9_-]{0,63}/}
#                          rails_performance        /rails/performance                                                                                RailsPerformance::Engine
#           turbo_recede_historical_location GET    /recede_historical_location(.:format)                                                             turbo/native/navigation#recede
#           turbo_resume_historical_location GET    /resume_historical_location(.:format)                                                             turbo/native/navigation#resume
#          turbo_refresh_historical_location GET    /refresh_historical_location(.:format)                                                            turbo/native/navigation#refresh
#              rails_postmark_inbound_emails POST   /rails/action_mailbox/postmark/inbound_emails(.:format)                                           action_mailbox/ingresses/postmark/inbound_emails#create
#                 rails_relay_inbound_emails POST   /rails/action_mailbox/relay/inbound_emails(.:format)                                              action_mailbox/ingresses/relay/inbound_emails#create
#              rails_sendgrid_inbound_emails POST   /rails/action_mailbox/sendgrid/inbound_emails(.:format)                                           action_mailbox/ingresses/sendgrid/inbound_emails#create
#        rails_mandrill_inbound_health_check GET    /rails/action_mailbox/mandrill/inbound_emails(.:format)                                           action_mailbox/ingresses/mandrill/inbound_emails#health_check
#              rails_mandrill_inbound_emails POST   /rails/action_mailbox/mandrill/inbound_emails(.:format)                                           action_mailbox/ingresses/mandrill/inbound_emails#create
#               rails_mailgun_inbound_emails POST   /rails/action_mailbox/mailgun/inbound_emails/mime(.:format)                                       action_mailbox/ingresses/mailgun/inbound_emails#create
#             rails_conductor_inbound_emails GET    /rails/conductor/action_mailbox/inbound_emails(.:format)                                          rails/conductor/action_mailbox/inbound_emails#index
#                                            POST   /rails/conductor/action_mailbox/inbound_emails(.:format)                                          rails/conductor/action_mailbox/inbound_emails#create
#          new_rails_conductor_inbound_email GET    /rails/conductor/action_mailbox/inbound_emails/new(.:format)                                      rails/conductor/action_mailbox/inbound_emails#new
#              rails_conductor_inbound_email GET    /rails/conductor/action_mailbox/inbound_emails/:id(.:format)                                      rails/conductor/action_mailbox/inbound_emails#show
#   new_rails_conductor_inbound_email_source GET    /rails/conductor/action_mailbox/inbound_emails/sources/new(.:format)                              rails/conductor/action_mailbox/inbound_emails/sources#new
#      rails_conductor_inbound_email_sources POST   /rails/conductor/action_mailbox/inbound_emails/sources(.:format)                                  rails/conductor/action_mailbox/inbound_emails/sources#create
#      rails_conductor_inbound_email_reroute POST   /rails/conductor/action_mailbox/:inbound_email_id/reroute(.:format)                               rails/conductor/action_mailbox/reroutes#create
#   rails_conductor_inbound_email_incinerate POST   /rails/conductor/action_mailbox/:inbound_email_id/incinerate(.:format)                            rails/conductor/action_mailbox/incinerates#create
#                         rails_service_blob GET    /rails/active_storage/blobs/redirect/:signed_id/*filename(.:format)                               active_storage/blobs/redirect#show
#                   rails_service_blob_proxy GET    /rails/active_storage/blobs/proxy/:signed_id/*filename(.:format)                                  active_storage/blobs/proxy#show
#                                            GET    /rails/active_storage/blobs/:signed_id/*filename(.:format)                                        active_storage/blobs/redirect#show
#                  rails_blob_representation GET    /rails/active_storage/representations/redirect/:signed_blob_id/:variation_key/*filename(.:format) active_storage/representations/redirect#show
#            rails_blob_representation_proxy GET    /rails/active_storage/representations/proxy/:signed_blob_id/:variation_key/*filename(.:format)    active_storage/representations/proxy#show
#                                            GET    /rails/active_storage/representations/:signed_blob_id/:variation_key/*filename(.:format)          active_storage/representations/redirect#show
#                         rails_disk_service GET    /rails/active_storage/disk/:encoded_key/*filename(.:format)                                       active_storage/disk#show
#                  update_rails_disk_service PUT    /rails/active_storage/disk/:encoded_token(.:format)                                               active_storage/disk#update
#                       rails_direct_uploads POST   /rails/active_storage/direct_uploads(.:format)                                                    active_storage/direct_uploads#create
#
# Routes for LetterOpenerWeb::Engine:
#        Prefix Verb URI Pattern                      Controller#Action
#       letters GET  /                                letter_opener_web/letters#index
# clear_letters POST /clear(.:format)                 letter_opener_web/letters#clear
#        letter GET  /:id(/:style)(.:format)          letter_opener_web/letters#show
# delete_letter POST /:id/delete(.:format)            letter_opener_web/letters#destroy
#               GET  /:id/attachments/:file(.:format) letter_opener_web/letters#attachment {file: /[^\/]+/}
#
# Routes for ActionMailbox::Engine:
# No routes defined.
#
# Routes for ActiveInsights::Engine:
#                          Prefix Verb URI Pattern                                                    Controller#Action
#                        requests GET  /requests(.:format)                                            active_insights/requests#index
#                            jobs GET  /jobs(.:format)                                                active_insights/jobs#index
#                                 GET  /jobs/:date(.:format)                                          active_insights/jobs#index
#                                 GET  /requests/:date(.:format)                                      active_insights/requests#index
#                 rpm_redirection GET  /requests/rpm/redirection(.:format)                            active_insights/rpm#redirection
#                             rpm GET  /requests/:date/rpm(.:format)                                  active_insights/rpm#index
#   requests_p_values_redirection GET  /requests/p_values/redirection(.:format)                       active_insights/requests_p_values#redirection
#               requests_p_values GET  /requests/:date/p_values(.:format)                             active_insights/requests_p_values#index
#             controller_p_values GET  /requests/:date/:formatted_controller/p_values(.:format)       active_insights/requests_p_values#index
# controller_p_values_redirection GET  /requests/:formatted_controller/p_values/redirection(.:format) active_insights/requests_p_values#redirection
#                 jpm_redirection GET  /jobs/jpm/redirection(.:format)                                active_insights/jpm#redirection
#                             jpm GET  /jobs/:date/jpm(.:format)                                      active_insights/jpm#index
#       jobs_p_values_redirection GET  /jobs/p_values/redirection(.:format)                           active_insights/jobs_p_values#redirection
#                   jobs_p_values GET  /jobs/:date/p_values(.:format)                                 active_insights/jobs_p_values#index
#                    job_p_values GET  /jobs/:date/:job/p_values(.:format)                            active_insights/jobs_p_values#index
#        job_p_values_redirection GET  /jobs/:job/p_values/redirection(.:format)                      active_insights/jobs_p_values#redirection
#                    jobs_latency GET  /jobs/:date/latencies(.:format)                                active_insights/jobs_latencies#index
#        jobs_latency_redirection GET  /jobs/latencies/redirection(.:format)                          active_insights/jobs_latencies#redirection
#                            root GET  /                                                              active_insights/requests#index
#
# Routes for Blazer::Engine:
#            Prefix Verb   URI Pattern                       Controller#Action
#       run_queries POST   /queries/run(.:format)            blazer/queries#run
#    cancel_queries POST   /queries/cancel(.:format)         blazer/queries#cancel
#     refresh_query POST   /queries/:id/refresh(.:format)    blazer/queries#refresh
#    tables_queries GET    /queries/tables(.:format)         blazer/queries#tables
#    schema_queries GET    /queries/schema(.:format)         blazer/queries#schema
#      docs_queries GET    /queries/docs(.:format)           blazer/queries#docs
#           queries GET    /queries(.:format)                blazer/queries#index
#                   POST   /queries(.:format)                blazer/queries#create
#         new_query GET    /queries/new(.:format)            blazer/queries#new
#        edit_query GET    /queries/:id/edit(.:format)       blazer/queries#edit
#             query GET    /queries/:id(.:format)            blazer/queries#show
#                   PATCH  /queries/:id(.:format)            blazer/queries#update
#                   PUT    /queries/:id(.:format)            blazer/queries#update
#                   DELETE /queries/:id(.:format)            blazer/queries#destroy
#         run_check GET    /checks/:id/run(.:format)         blazer/checks#run
#            checks GET    /checks(.:format)                 blazer/checks#index
#                   POST   /checks(.:format)                 blazer/checks#create
#         new_check GET    /checks/new(.:format)             blazer/checks#new
#        edit_check GET    /checks/:id/edit(.:format)        blazer/checks#edit
#             check PATCH  /checks/:id(.:format)             blazer/checks#update
#                   PUT    /checks/:id(.:format)             blazer/checks#update
#                   DELETE /checks/:id(.:format)             blazer/checks#destroy
# refresh_dashboard POST   /dashboards/:id/refresh(.:format) blazer/dashboards#refresh
#        dashboards POST   /dashboards(.:format)             blazer/dashboards#create
#     new_dashboard GET    /dashboards/new(.:format)         blazer/dashboards#new
#    edit_dashboard GET    /dashboards/:id/edit(.:format)    blazer/dashboards#edit
#         dashboard GET    /dashboards/:id(.:format)         blazer/dashboards#show
#                   PATCH  /dashboards/:id(.:format)         blazer/dashboards#update
#                   PUT    /dashboards/:id(.:format)         blazer/dashboards#update
#                   DELETE /dashboards/:id(.:format)         blazer/dashboards#destroy
#              root GET    /                                 blazer/queries#home
#
# Routes for MissionControl::Jobs::Engine:
#                      Prefix Verb   URI Pattern                                                    Controller#Action
#     application_queue_pause DELETE /applications/:application_id/queues/:queue_id/pause(.:format) mission_control/jobs/queues/pauses#destroy
#                             POST   /applications/:application_id/queues/:queue_id/pause(.:format) mission_control/jobs/queues/pauses#create
#          application_queues GET    /applications/:application_id/queues(.:format)                 mission_control/jobs/queues#index
#           application_queue GET    /applications/:application_id/queues/:id(.:format)             mission_control/jobs/queues#show
#       application_job_retry POST   /applications/:application_id/jobs/:job_id/retry(.:format)     mission_control/jobs/retries#create
#     application_job_discard POST   /applications/:application_id/jobs/:job_id/discard(.:format)   mission_control/jobs/discards#create
#    application_job_dispatch POST   /applications/:application_id/jobs/:job_id/dispatch(.:format)  mission_control/jobs/dispatches#create
#    application_bulk_retries POST   /applications/:application_id/jobs/bulk_retries(.:format)      mission_control/jobs/bulk_retries#create
#   application_bulk_discards POST   /applications/:application_id/jobs/bulk_discards(.:format)     mission_control/jobs/bulk_discards#create
#             application_job GET    /applications/:application_id/jobs/:id(.:format)               mission_control/jobs/jobs#show
#            application_jobs GET    /applications/:application_id/:status/jobs(.:format)           mission_control/jobs/jobs#index
#         application_workers GET    /applications/:application_id/workers(.:format)                mission_control/jobs/workers#index
#          application_worker GET    /applications/:application_id/workers/:id(.:format)            mission_control/jobs/workers#show
# application_recurring_tasks GET    /applications/:application_id/recurring_tasks(.:format)        mission_control/jobs/recurring_tasks#index
#  application_recurring_task GET    /applications/:application_id/recurring_tasks/:id(.:format)    mission_control/jobs/recurring_tasks#show
#                             PATCH  /applications/:application_id/recurring_tasks/:id(.:format)    mission_control/jobs/recurring_tasks#update
#                             PUT    /applications/:application_id/recurring_tasks/:id(.:format)    mission_control/jobs/recurring_tasks#update
#                      queues GET    /queues(.:format)                                              mission_control/jobs/queues#index
#                       queue GET    /queues/:id(.:format)                                          mission_control/jobs/queues#show
#                         job GET    /jobs/:id(.:format)                                            mission_control/jobs/jobs#show
#                        jobs GET    /:status/jobs(.:format)                                        mission_control/jobs/jobs#index
#                        root GET    /                                                              mission_control/jobs/queues#index
#
# Routes for RailsPerformance::Engine:
#                        Prefix Verb URI Pattern             Controller#Action
#                  engine_asset GET  /assets/*file(.:format) Inline handler (Proc/Lambda)
#             rails_performance GET  /                       rails_performance/rails_performance#index
#    rails_performance_requests GET  /requests(.:format)     rails_performance/rails_performance#requests
#     rails_performance_crashes GET  /crashes(.:format)      rails_performance/rails_performance#crashes
#      rails_performance_recent GET  /recent(.:format)       rails_performance/rails_performance#recent
#        rails_performance_slow GET  /slow(.:format)         rails_performance/rails_performance#slow
#       rails_performance_trace GET  /trace/:id(.:format)    rails_performance/rails_performance#trace
#     rails_performance_summary GET  /summary(.:format)      rails_performance/rails_performance#summary
#     rails_performance_sidekiq GET  /sidekiq(.:format)      rails_performance/rails_performance#sidekiq
# rails_performance_delayed_job GET  /delayed_job(.:format)  rails_performance/rails_performance#delayed_job
#       rails_performance_grape GET  /grape(.:format)        rails_performance/rails_performance#grape
#        rails_performance_rake GET  /rake(.:format)         rails_performance/rails_performance#rake
#      rails_performance_custom GET  /custom(.:format)       rails_performance/rails_performance#custom
#   rails_performance_resources GET  /resources(.:format)    rails_performance/rails_performance#resources

Rails.application.routes.draw do
  # Sitemap
  get "sitemap.xml", to: "sitemaps#index", as: :sitemap, defaults: { format: :xml }

  # Static OG images
  get "og/:page", to: "og_images#show", as: :og_image, defaults: { format: :png }
  # Landing
  root "landing#index"
  # get "marketing", to: "landing#marketing"

  # RSVPs
  resources :rsvps, only: [ :create ] do
    patch :user_ref, on: :collection
  end
  get "rsvps/confirm/:token", to: "rsvps#confirm", as: :confirm_rsvp
  get "tic_tac", to: "rsvps#tic_tac", as: :tic_tac, defaults: { format: :text }

  # Shop
  get "shop", to: "shop#index"
  get "shop/my_orders", to: "shop#my_orders"
  delete "shop/cancel_order/:order_id", to: "shop#cancel_order", as: :cancel_shop_order
  get "shop/order", to: "shop#order"
  post "shop/order", to: "shop#create_order"
  patch "shop/update_region", to: "shop#update_region"
  get "shop/category/:slug", to: "shop#category", as: :shop_category
  resources :shop_suggestions, only: [ :create ]

  # Report Reviews
  get "report-reviews/review/:token", to: "report_reviews#review", as: :review_report_token
  get "report-reviews/dismiss/:token", to: "report_reviews#dismiss", as: :dismiss_report_token

  # Voting
  get "rate/new", to: "votes#new", as: :new_rate
  resources :votes, only: [ :new, :create ]
  namespace :votes do
    resource :skip, only: :create
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Test error page for Sentry
  get "test_error" => "debug#error" unless Rails.env.production?

  # Letter opener web for development email preview
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"

    get "og_image_previews", to: "og_image_previews#index"
    get "og_image_previews/*id", to: "og_image_previews#show", as: :og_image_preview

  end

  # Action Mailbox for incoming HCB and tracking emails
  mount ActionMailbox::Engine => "/rails/action_mailbox"
  mount ActiveInsights::Engine => "/insights"

  # hackatime should not create a new session; it's used for linking
  get "auth/hackatime/callback", to: "identities#hackatime"

  # Sessions
  get "auth/:provider/callback", to: "sessions#create"
  get "/auth/failure", to: "sessions#failure"
  delete "logout", to: "sessions#destroy"
  get "dev_login", to: "sessions#dev_login", as: :dev_login_auto if Rails.env.development? || Rails.env.test?
  get "dev_login/:id", to: "sessions#dev_login", as: :dev_login if Rails.env.development? || Rails.env.test?

  # OAuth callback for HCA
  get "/oauth/callback", to: "sessions#create"

  # Home
  get "home", to: "home#index"

  # Leaderboard
  get "leaderboard", to: "leaderboard#index"

  # Events — listing of missions and (eventually) other themed events.
  resources :events, only: [ :index ]

  # My
  namespace :my do
    resource :balance, only: [ :show ]
    resource :settings, only: [ :update ] do
      post :streamer_mode, on: :member, action: :toggle_streamer_mode
    end
    resources :dismissals, only: [ :create ]
    post "verification/refresh", to: "verifications#refresh", as: :verification_refresh
    post "dev/pretend_idv", to: "dev_tools#pretend_idv", as: :pretend_idv_dev
  end
  get "my/achievements", to: "achievements#index", as: :my_achievements

  namespace :seller do
    resources :orders, only: %i[index show] do
      member do
        post :reveal_address
        post :mark_fulfilled
      end
    end
  end

  namespace :onboarding do
    post :start,                     to: "wizard#start"
    get  :welcome,                   to: "wizard#welcome"
    get  :birthday,                  to: "wizard#birthday"
    post :birthday,                  to: "wizard#submit_birthday"
    get  :age_gate,                  to: "wizard#age_gate"
    get  :experience,                to: "wizard#experience"
    post :experience,                to: "wizard#submit_experience"
    get  :experience_result,         to: "wizard#experience_result"
    get  :interests,                 to: "wizard#interests"
    post :interests,                 to: "wizard#submit_interests"
    get  :interests_result,          to: "wizard#interests_result"
    get  :name,                      to: "wizard#name"
    post :name,                      to: "wizard#submit_name"
  end

  namespace :admin, constraints: AdminConstraint do
    root to: "application#index"

    mount Blazer::Engine, at: "blazer", constraints: ->(request) {
      AdminConstraint.allow?(request, :access_blazer?)
    }

    mount Flipper::UI.app(Flipper), at: "flipper", constraints: ->(request) {
      AdminConstraint.allow?(request, :access_flipper?)
    }

    mount MissionControl::Jobs::Engine, at: "jobs", constraints: ->(request) {
      AdminConstraint.allow?(request, :access_jobs?)
    }

    resources :users, only: [ :index, :show, :update ] do
      scope module: :users do
        resources :roles,               only: [ :create, :destroy ], param: :name
        resource  :ban,                 only: [ :create, :destroy ]
        resource  :impersonation,       only: [ :create ]
        resources :feature_flags,       only: [ :create, :destroy ], param: :feature
        resource  :hackatime_sync,      only: [ :create ]
        resource  :order_rejection,     only: [ :create ]
        resources :balance_adjustments, only: [ :create ]
        resource  :grant_cancellation,  only: [ :create ]
        resource  :verification,        only: [ :create ]
        resource  :vote_balance,        only: [ :update ]
        resource  :ysws_override,       only: [ :update ]
        resources :votes,               only: [ :index ]
      end
    end

    resource :impersonation, only: [ :destroy ], controller: "users/impersonations"
    resources :projects, only: [ :index, :show ] do
      member do
        post :restore
        post :delete
        post :update_ship_status
        post :force_state
        get  :votes
      end
    end
    get "user-perms", to: "users#user_perms"
    resource :support, only: [ :show ], controller: "support/dashboards"
    resource :fraud, only: [ :show ], controller: "fraud/dashboards"
    resource :shop, only: [ :show ], controller: "shop/dashboard"
    post "shop/clear-carousel-cache", to: "shop/dashboard#clear_carousel_cache", as: :clear_carousel_cache
    namespace :shop do
      resources :items, only: [ :new, :create, :show, :edit, :update, :destroy ] do
        collection do
          post :preview_markdown
        end
        member do
          post :request_approval
        end
      end
      resources :orders, only: [ :index, :show ] do
        member do
          post :reveal_address
          post :reveal_phone
          post :approve
          post :review_order
          post :reject
          post :place_on_hold
          post :release_from_hold
          post :mark_fulfilled
          post :update_internal_notes
          post :assign_user
          post :cancel_hcb_grant
          post :refresh_verification
          post :send_to_theseus
          post :approve_verification_call
          post :force_state
        end
      end
      resources :suggestions, only: [ :index ] do
        member do
          post :dismiss
          post :disable_for_user
        end
      end
    end
    resources :messages, only: [ :index, :create ]
    resources :support_vibes, only: [ :index, :create ]
    resources :sw_vibes, only: [ :index ]
    resources :suspicious_votes, only: [ :index ]
    resources :audit_logs, only: [ :index, :show ]
    resources :reports, only: [ :index, :show ] do
      collection do
        post :process_demo_broken
      end
      member do
        post :review
        post :dismiss
      end
    end
    resources :fulfillment_payouts, only: [ :index, :show ] do
      member do
        post :approve
        post :reject
      end
      collection do
        post :trigger
      end
    end
  end

  # Mission management under /admin/ — the URL prefix is `admin`, but
  # AdminConstraint is intentionally NOT applied here so non-admin mission
  # owners can edit their own missions via Pundit's `MissionPolicy#manage?`.
  # Per-action authorization lives in Admin::MissionsController and the
  # Admin::Missions::* sub-resource controllers (admin-only actions vs
  # manage actions are gated separately inside those controllers).
  namespace :admin do
    resources :missions, param: :slug do
      member do
        post :restore
      end
      # Nested sub-resources live in the Admin::Missions:: namespace,
      # mirroring the Mission::Step / Mission::Prize / Mission::Membership /
      # Mission::ShopUnlock model namespace. `controller:` is set explicitly
      # because `scope module: :missions` doesn't reliably propagate inside
      # a parent `resources do ... end` block.
      resource  :guide_paste,    only: [ :create ],                  controller: "missions/guide_pastes"
      resource  :guide_preview,  only: [ :create ],                  controller: "missions/guide_previews"
      resources :memberships,    only: [ :create, :update, :destroy ], controller: "missions/memberships"
      resources :steps,          only: [ :create, :update, :destroy ], controller: "missions/steps"
      resource  :step_ordering,  only: [ :create ],                  controller: "missions/step_orderings"
      resources :prizes,         only: [ :create, :update, :destroy ], controller: "missions/prizes"
      resources :shop_unlocks,   only: [ :create, :destroy ],          controller: "missions/shop_unlocks"
    end

    namespace :certification do
      resources :ships, path: "ship_cert", only: [ :index, :show, :update ] do
        collection do
          get :next
        end
        member do
          post :claim
        end
      end

      resources :devlog_reviews, only: [ :update ]

      get "review", to: "ysws#index", as: "ysws_reviews"
      get "review/:id", to: "ysws#show", as: "ysws_review"
      post "review/:id/report_fraud", to: "ysws#report_fraud", as: "ysws_report_fraud"
    end
  end

  get "queue", to: "queue#index"

  # First-project setup flow — onboarding-style wizard for users creating their
  # first project. Mounted before `resources :projects` so /projects/setup/*
  # doesn't match the project show route.
  namespace :projects do
    get  "setup",               to: "setup#idea",          as: :setup
    post "setup/idea",          to: "setup#submit_idea",   as: :setup_submit_idea
    get  "setup/name",          to: "setup#name",          as: :setup_name
    post "setup/name",          to: "setup#submit_name",   as: :setup_submit_name
    get  "setup/missions",      to: "setup#missions",      as: :setup_missions
    post "setup/missions",      to: "setup#submit_mission", as: :setup_submit_mission
    get  "setup/link_account",  to: "setup#link_account",  as: :setup_link_account
    get  "setup/welcome",       to: "setup#welcome",       as: :setup_welcome
  end

  # Projects — public index lives on the user profile projects section; only
  # show/new/edit/update/destroy and the nested resources are exposed here.
  resources :projects, shallow: true, except: [ :index ] do
    post :add_test_time, on: :member
    resources :memberships, only: [ :create, :destroy ], module: :projects
    resources :devlogs, only: %i[create edit update destroy], module: :projects, shallow: false do
      member do
        get :versions
      end
      collection do
        get :preview_time
      end
    end
    resources :reports, only: [ :create ], module: :projects
    resource :og_image, only: [ :show ], module: :projects, defaults: { format: :png }
    resource :ships, only: [ :new, :create ], module: :projects do
      # Wizard steps, one route per page (rather than ?step=N query param):
      #   new      → refresher
      #   info     → project info form
      #   review   → review-instructions form (GET only — POST goes to the
      #              nested :review resource below, which persists the value
      #              into the session wizard and redirects to compose)
      #   compose  → final ship composer
      get :info,    on: :member
      get :review,  on: :member, action: :review_step
      get :compose, on: :member
      resource :review, only: [ :create ], module: :ships
    end
    resource :mission, only: [ :create, :destroy ], module: :projects, controller: "missions"
    resource :magic, only: [ :create, :destroy ], module: :projects, controller: "magic"
    resources :mission_section_completions,
              only: [ :create, :destroy ],
              module: :projects,
              param: :mission_step_id
    member do
      get :readme
      post :follow
      delete :unfollow
    end
  end

  # Devlog likes and comments
  resources :devlogs, only: [] do
    resource :like, only: [ :create, :destroy ]
    resources :comments, only: [ :create, :destroy ]
  end

  # Public user profiles
  resources :users, only: [ :show, :update ] do
    resource :og_image, only: [ :show ], module: :users, defaults: { format: :png }
    resource :follow, only: [ :create, :destroy ]
    member do
      get :devlogs,  action: :show, defaults: { tab: "devlogs" }
      get :replies,  action: :show, defaults: { tab: "replies" }
      get :projects, action: :show, defaults: { tab: "projects" }
      get :followers
      get :following
    end
  end

  resource :username_availability, only: [ :show ], controller: "users/username_availabilities"

  # Autocomplete search endpoints (used by the bio editor and elsewhere).
  get "search/users",    to: "search#users",    as: :search_users
  get "search/projects", to: "search#projects", as: :search_projects

  get "edu", to: "landing#edu", as: :edu

  # Guides
  resources :guides, only: [ :index, :show ]

  # Missions (public listing + show page).
  # Project-side / reviewer-queue / admin-managed missions surfaces ship in later PRs.
  resources :missions, only: [ :index, :show ], param: :slug do
    resource :og_image, only: [ :show ], module: :missions, defaults: { format: :png }
    member do
      get :guide
    end
  end

  # Reviewer queue.
  resources :mission_submissions, only: [ :index, :show ] do
    member do
      post :approve
      post :reject
      post :undo
      get  :redeem
    end
  end

  # Branded error pages. config.exceptions_app routes failures back through the
  # router with PATH_INFO set to "/<status>", so each status that can surface
  # (including from requests that never reach a controller) needs a match for
  # every verb. Declared before the "/:ref" catch so numeric codes don't fall
  # through to landing#index.
  match "/400", to: "errors#bad_request",           via: :all
  match "/404", to: "errors#not_found",             via: :all
  match "/406", to: "errors#not_acceptable",        via: :all
  match "/422", to: "errors#unprocessable_entity",  via: :all
  match "/500", to: "errors#internal_server_error", via: :all

  get "/:ref", to: "landing#index", constraints: { ref: /[a-z0-9][a-z0-9_-]{0,63}/ }
end
