FROM ruby:2.5-alpine

ENV APP_HOME /opt/app

RUN gem install bundler

WORKDIR ${APP_HOME}

COPY Gemfile Gemfile.lock ${APP_HOME}/

RUN bundle install

COPY . ${APP_HOME}

EXPOSE 3000

CMD [ "bundle", "exec", "rackup", "--host", "0.0.0.0", "--port", "3000"]
