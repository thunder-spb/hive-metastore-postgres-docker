FROM openjdk:8-slim

LABEL maintainer="Amom Mendes"
LABEL maintainer="Alexzander thunder Shevchenko"
LABEL hive-metastore-version="3.0.0"
LABEL postgresql-jdbc-version="42.2.16"
LABEL hadoop-version="3.2.0"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH

ARG HADOOP_VERSION=3.2.0
ARG HIVE_METASTORE_VERSION=3.0.0
ARG POSTGRESQL_JDBC_VERSION=42.2.16
ARG GOTEMPLATE_VERSION=3.6.0

RUN apt-get update \
  && apt-get install -y curl --no-install-recommends \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install Gomplate
RUN curl -sfSL https://github.com/hairyhenderson/gomplate/releases/download/v${GOTEMPLATE_VERSION}/gomplate_${TARGETOS}-${TARGETARCH} -o /usr/local/bin/gomplate \
  && chmod 755 /usr/local/bin/gomplate

WORKDIR /opt
COPY metastore-log4j2.properties .

# Set Hadoop/HiveMetastore variables and Classpath
ENV HADOOP_HOME="/opt/hadoop"
ENV METASTORE_HOME="/opt/hive-metastore"
ENV HADOOP_CLASSPATH="${HADOOP_HOME}/share/hadoop/tools/lib/*:${METASTORE_HOME}/lib"
ENV PATH="${HADOOP_HOME}/bin:${METASTORE_HOME}/lib/:${HADOOP_HOME}/share/hadoop/tools/lib/:${PATH}"

# Download and extract the Hadoop binary package.
RUN curl -s https://archive.apache.org/dist/hadoop/core/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz | tar xz -C /opt/  \
  && ln -s ${HADOOP_HOME}-${HADOOP_VERSION} ${HADOOP_HOME} \
  && rm -r ${HADOOP_HOME}/share/doc

# Add S3a jars to the Hadoop classpath
RUN cp ${HADOOP_HOME}/share/hadoop/tools/lib/hadoop-aws* ${HADOOP_HOME}/share/hadoop/common/lib/ \
  && cp ${HADOOP_HOME}/share/hadoop/tools/lib/aws-java-sdk* ${HADOOP_HOME}/share/hadoop/common/lib/

# Download and install the standalone metastore binary
# (Standalone Metastore is available after 3.0.0 version)
RUN curl -s http://apache.uvigo.es/hive/hive-standalone-metastore-${HIVE_METASTORE_VERSION}/hive-standalone-metastore-${HIVE_METASTORE_VERSION}-bin.tar.gz \
        | tar xz -C /opt/ \
  && ln -s /opt/apache-hive-metastore-${HIVE_METASTORE_VERSION}-bin ${METASTORE_HOME}
# Add jars to the Hive Metastore classpath
RUN cp ${HADOOP_HOME}/share/hadoop/tools/lib/hadoop-aws* ${METASTORE_HOME}/lib/ \
  && cp ${HADOOP_HOME}/share/hadoop/tools/lib/aws-java-sdk* ${METASTORE_HOME}/lib/ \
  && curl -L https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-web/2.17.2/log4j-web-2.17.2.jar -o \
  ${METASTORE_HOME}/lib/log4j-web-2.17.2.jar

# Download and install the postgres connector used by HiveMetastore
## TODO: do not chmod 775!
RUN curl -L https://jdbc.postgresql.org/download/postgresql-${POSTGRESQL_JDBC_VERSION}.jar -o /opt/postgresql-${POSTGRESQL_JDBC_VERSION}.jar \
  && cp /opt/postgresql-*.jar ${HADOOP_HOME}/share/hadoop/common/lib/ && chmod -R 775 ${HADOOP_HOME}/share/hadoop/common/lib/* \
  && cp /opt/postgresql-*.jar ${METASTORE_HOME}/lib/ && chmod -R 775 ${METASTORE_HOME}/lib/*

COPY entrypoint.sh ${METASTORE_HOME}/bin/
RUN chmod 775 ${METASTORE_HOME}/bin/entrypoint.sh

# Metastore URI Port
EXPOSE 9083

WORKDIR ${METASTORE_HOME}

# Apply Hive custom configurations and start Metastore Service through entrypoint.sh file
#
# We need to use the exec form to avoid running our command in a subshell and omitting signals,
# thus being unable to shut down gracefully:
# https://docs.docker.com/engine/reference/builder/#entrypoint
#
# Also we need to use relative path, because the exec form does not invoke a command shell,
# thus normal shell processing does not happen:
# https://docs.docker.com/engine/reference/builder/#exec-form-entrypoint-example

CMD ["bin/entrypoint.sh"]
