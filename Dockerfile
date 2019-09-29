FROM ruby:2.5-slim

ENV APP_HOME /opt/app

RUN apt update \
        # Required by sorbet
	&& apt install -y git

RUN gem install bundler

WORKDIR ${APP_HOME}

COPY Gemfile Gemfile.lock ${APP_HOME}/

RUN bundle install

COPY . ${APP_HOME}

EXPOSE 3000

CMD [ "bundle", "exec", "rackup", "--host", "0.0.0.0", "--port", "3000"]
