bundle install
cp example.env .env
bin/rails db:migrate
bin/rails db:seed