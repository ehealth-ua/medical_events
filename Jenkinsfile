pipeline {
  agent none
    environment {
      PROJECT_NAME = 'medical-events'
      INSTANCE_TYPE = 'n1-highcpu-16'
      NO_ECTO_SETUP = 'true'
      RD = "b${UUID.randomUUID().toString()}"
      RD_CROP = "b${RD.take(14)}"
      NAME = "${RD.take(5)}" 
}  
  stages {
    stage('Prepare instance') {
      agent {
        kubernetes {
          label 'create-instance'
          defaultContainer 'jnlp'
        }
      }
      steps {
        container(name: 'gcloud', shell: '/bin/sh') {
          withCredentials([file(credentialsId: 'e7e3e6df-8ef5-4738-a4d5-f56bb02a8bb2', variable: 'KEYFILE')]) {
            sh 'apk update && apk add curl bash'
            sh 'gcloud auth activate-service-account jenkins-pool@ehealth-162117.iam.gserviceaccount.com --key-file=${KEYFILE} --project=ehealth-162117'
            sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/create_instance.sh -o create_instance.sh; bash ./create_instance.sh'
          }
          slackSend (color: '#8E24AA', message: "Instance for ${GIT_URL[19..-5]}@$GIT_BRANCH created")
        }
      }
      post { 
        success {
          slackSend (color: 'good', message: "Build <${RUN_CHANGES_DISPLAY_URL[0..-8]}status|#$BUILD_NUMBER> (<${GIT_URL[0..-5]}/commit/$GIT_COMMIT|${GIT_COMMIT.take(7)}>) of ${GIT_URL[19..-5]}@$GIT_BRANCH by $GIT_COMMITTER_NAME STARTED")
        }
        failure {
          slackSend (color: 'danger', message: "Build <${RUN_CHANGES_DISPLAY_URL[0..-8]}status|#$BUILD_NUMBER> (<${GIT_URL[0..-5]}/commit/$GIT_COMMIT|${GIT_COMMIT.take(7)}>) of ${GIT_URL[19..-5]}@$GIT_BRANCH by $GIT_COMMITTER_NAME FAILED to start")
        }
        aborted {
          slackSend (color: 'warning', message: "Build <${RUN_CHANGES_DISPLAY_URL[0..-8]}status|#$BUILD_NUMBER> (<${GIT_URL[0..-5]}/commit/$GIT_COMMIT|${GIT_COMMIT.take(7)}>) of ${GIT_URL[19..-5]}@$GIT_BRANCH by $GIT_COMMITTER_NAME ABORTED before start")
        }
      }
}
    stage('Test') {
      environment {
        MIX_ENV = 'test'
        DOCKER_NAMESPACE = 'edenlabllc'
        POSTGRES_VERSION = '9.6'
        POSTGRES_USER = 'postgres'
        POSTGRES_PASSWORD = 'postgres'
        POSTGRES_DB = 'postgres'        
      }
      agent {
        kubernetes {
          label "medical-events-test-$BUILD_ID-$NAME"
          defaultContainer 'jnlp'
          yaml """
apiVersion: v1
kind: Pod
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "$RD_CROP"
    effect: "NoSchedule"
  containers:
  - name: elixir
    image: edenlabllc/ubuntu18-otp-25-2-5-elixir:1.8.1
    resources:
      limits:
        memory: 10048Mi
      requests:
        cpu: 20m
        memory: 64Mi        
    command:
    - cat
    tty: true
  - name: mongo
    image: edenlabllc/alpine-mongo:4.0.1-0
    resources:
      limits:
        memory: 512Mi
      requests:
        cpu: 200m
        memory: 256Mi       
    ports:
    - containerPort: 27017
    tty: true
  - name: redis
    image: redis:4-alpine3.9
    resources:
      limits:
        memory: 512Mi
      requests:
        cpu: 200m
        memory: 256Mi       
    ports:
    - containerPort: 6379
    tty: true
  - name: kafkazookeeper
    image: edenlabllc/kafka-zookeeper:2.1.0
    resources:
      limits:
        memory: 512Mi
      requests:
        cpu: 20m
        memory: 64Mi       
    ports:
    - containerPort: 2181
    - containerPort: 9092
    env:
    - name: ADVERTISED_HOST
      valueFrom:
        fieldRef:
          fieldPath: status.podIP      
    tty: true                   
  nodeSelector:
    node: "$RD_CROP"
"""
            }
          }
          steps {
            container(name: 'kafkazookeeper', shell: '/bin/sh') {
              sh '''
                sleep 15;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic medical_events --partitions 1 --replication-factor 1;
                sleep 5;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic person_events --partitions 1 --replication-factor 1;
                sleep 5;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic mongo_events --partitions 1 --replication-factor 1
              '''
            }
            container(name: 'elixir', shell: '/bin/sh') {
              sh '''
                apt-get install -y jq curl bash git libncurses5-dev zlib1g-dev ca-certificates openssl make g++
                git submodule sync & git submodule update
                cat apps/core/config/config.exs
                mix local.hex --force;
                mix local.rebar --force;
                mix deps.get;
                mix deps.compile;
                curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/tests.sh -o tests.sh; bash ./tests.sh
              '''
            }
          }
        }
    stage('Build') {
      environment {
        MIX_ENV = 'test'
        DOCKER_NAMESPACE = 'edenlabllc'
        NO_ECTO_SETUP = 'true'
      }
      failFast true      
      parallel {
        stage('Build medical-events-api') {
          environment {
            APPS='[{"app":"medical_events_api","chart":"medical-events-api","namespace":"me","deployment":"api-medical-events","label":"api-medical-events"}]'
            DOCKER_CREDENTIALS = 'credentials("20c2924a-6114-46dc-8e39-bfadd1cf8acf")'
          }
          agent {
            kubernetes {
              label "medical-events-api-$BUILD_ID-$NAME"
              defaultContainer 'jnlp'
              yaml """
apiVersion: v1
kind: Pod
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "$RD_CROP"
    effect: "NoSchedule"
  containers:
  - name: docker
    image: edenlabllc/docker:18.09-alpine-elixir-1.8.1
    resources:
      limits:
        memory: 512Mi
      requests:
        cpu: 500m
        memory: 128Mi       
    env:
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: DOCKER_HOST 
      value: tcp://localhost:2375           
    command:
    - cat
    tty: true
  - name: kafkazookeeper
    image: edenlabllc/kafka-zookeeper:2.1.0
    resources:
      limits:
        memory: 512Mi
      requests:
        cpu: 200m
        memory: 256Mi       
    ports:
    - containerPort: 2181
    - containerPort: 9092
    env:
    - name: ADVERTISED_HOST
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    tty: true
  - name: dind
    image: docker:18.09.2-dind
    resources:
      limits:
        memory: 2048Mi
      requests:
        cpu: 200m
        memory: 256Mi       
    securityContext: 
        privileged: true 
    ports:
    - containerPort: 2375
    tty: true
    volumeMounts: 
    - name: docker-graph-storage 
      mountPath: /var/lib/docker   
  - name: redis
    image: redis:4.0-alpine3.9
    resources:
      limits:
        memory: 128Mi
      requests:
        cpu: 200m
        memory: 32Mi       
    ports:
    - containerPort: 6379 
    tty: true
  volumes:
  - name: docker-graph-storage 
    emptyDir: {}  
  nodeSelector:
    node: "$RD_CROP"
"""
            }
          }
          steps {
            container(name: 'kafkazookeeper', shell: '/bin/sh') {
              sh '''
                sleep 15;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic medical_events --partitions 1 --replication-factor 1;
                sleep 5;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic person_events --partitions 1 --replication-factor 1;
                sleep 5;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic mongo_events --partitions 1 --replication-factor 1
              '''
            }          
            container(name: 'docker', shell: '/bin/sh') {
              sh 'sed -i "s/travis/${POD_IP}/g" .env'
              sh 'echo -----Build Docker container for EHealth API-------'
              sh 'apk update && apk add --no-cache jq curl bash elixir git ncurses-libs zlib ca-certificates openssl erlang-crypto  openssl make g++ erlang-runtime-tools;'
              sh 'echo " ---- step: Build docker image ---- ";'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_new/build-container.sh -o build-container.sh; bash ./build-container.sh'
              sh 'echo " ---- step: Start docker container ---- ";'
              sh 'mix local.rebar --force'
              sh 'mix local.hex --force'
              sh 'mix deps.get'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_new/start-container.sh -o start-container.sh; bash ./start-container.sh'
              withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                sh 'echo " ---- step: Push docker image ---- ";'
                sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_new/push-changes.sh -o push-changes.sh; bash ./push-changes.sh'
              }
            }
          }
        }    
        stage('Build event-consumer') {
          environment {
            APPS='[{"app":"event_consumer","chart":"medical-events-api","namespace":"me","deployment":"event-consumer","label":"event-consumer"}]'
            DOCKER_CREDENTIALS = 'credentials("20c2924a-6114-46dc-8e39-bfadd1cf8acf")'
          }
          agent {
            kubernetes {
              label "event-consumer-$BUILD_ID-$NAME"
              defaultContainer 'jnlp'
              yaml """
apiVersion: v1
kind: Pod
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "$RD_CROP"
    effect: "NoSchedule"
  containers:
  - name: docker
    image: edenlabllc/docker:18.09-alpine-elixir-1.8.1
    resources:
      limits:
        memory: 512Mi
      requests:
        cpu: 500m
        memory: 128Mi
    env:
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: DOCKER_HOST 
      value: tcp://localhost:2375          
    command:
    - cat
    tty: true
  - name: kafkazookeeper
    image: edenlabllc/kafka-zookeeper:2.1.0
    resources:
      limits:
        memory: 512Mi
      requests:
        cpu: 200m
        memory: 256Mi     
    ports:
    - containerPort: 2181
    - containerPort: 9092
    env:
    - name: ADVERTISED_HOST
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    tty: true
  - name: mongo
    image: edenlabllc/alpine-mongo:4.0.1-0
    ports:
    - containerPort: 27017
    tty: true
    resources:
      requests:
        memory: "64Mi"
        cpu: "50m"
      limits:
        memory: "256Mi"
        cpu: "300m"
  - name: redis
    image: redis:4.0-alpine3.9
    resources:
      limits:
        memory: 512Mi
      requests:
        cpu: 200m
        memory: 256Mi      
    ports:
    - containerPort: 6379 
    tty: true     
  - name: dind
    image: docker:18.09.2-dind
    resources:
      limits:
        memory: 2048Mi
      requests:
        cpu: 200m
        memory: 256Mi     
    securityContext: 
        privileged: true 
    ports:
    - containerPort: 2375
    tty: true
    volumeMounts: 
    - name: docker-graph-storage 
      mountPath: /var/lib/docker            
  volumes:
  - name: docker-graph-storage 
    emptyDir: {}
  nodeSelector:
    node: "$RD_CROP"    
"""
            }
          }
          steps {
            container(name: 'kafkazookeeper', shell: '/bin/sh') {
              sh '''
                sleep 15;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic medical_events --partitions 1 --replication-factor 1;
                sleep 5;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic person_events --partitions 1 --replication-factor 1;
                sleep 5;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic mongo_events --partitions 1 --replication-factor 1
              '''
            }          
            container(name: 'docker', shell: '/bin/sh') {
              sh 'sed -i "s/travis/${POD_IP}/g" .env'
              sh 'echo -----Build Docker container for Casher-------'
              sh 'apk update && apk add --no-cache jq curl bash elixir git ncurses-libs zlib ca-certificates openssl make g++ erlang-crypto erlang-runtime-tools;'
              sh 'echo " ---- step: Build docker image ---- ";'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_new/build-container.sh -o build-container.sh; bash ./build-container.sh'
              sh 'echo " ---- step: Start docker container ---- ";'
              sh 'mix local.rebar --force'
              sh 'mix local.hex --force'
              sh 'mix deps.get'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_new/start-container.sh -o start-container.sh; bash ./start-container.sh'
              withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                sh 'echo " ---- step: Push docker image ---- ";'
                sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_new/push-changes.sh -o push-changes.sh; bash ./push-changes.sh'
              }
            }
          }
        }
        stage('Build person-consumer') {
          environment {
            APPS='[{"app":"person_consumer","chart":"medical-events-api","namespace":"me","deployment":"person-consumer","label":"person-consumer"}]'
            DOCKER_CREDENTIALS = 'credentials("20c2924a-6114-46dc-8e39-bfadd1cf8acf")'
          }
          agent {
            kubernetes {
              label "person-consumer-build-$BUILD_ID-$NAME"
              defaultContainer 'jnlp'
              yaml """
apiVersion: v1
kind: Pod
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "$RD_CROP"
    effect: "NoSchedule"
  containers:
  - name: docker
    image: edenlabllc/docker:18.09-alpine-elixir-1.8.1
    resources:
      limits:
        memory: 512Mi
      requests:
        cpu: 500m
        memory: 128Mi        
    env:
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: DOCKER_HOST 
      value: tcp://localhost:2375        
    command:
    - cat
    tty: true
  - name: dind
    image: docker:18.09.2-dind
    resources:
      limits:
        memory: 2048Mi
      requests:
        cpu: 200m
        memory: 256Mi        
    securityContext: 
        privileged: true 
    ports:
    - containerPort: 2375
    tty: true
    volumeMounts: 
    - name: docker-graph-storage 
      mountPath: /var/lib/docker        
  - name: kafkazookeeper
    image: edenlabllc/kafka-zookeeper:2.1.0
    resources:
      limits:
        memory: 512Mi
      requests:
        cpu: 200m
        memory: 256Mi         
    ports:
    - containerPort: 2181
    - containerPort: 9092
    env:
    - name: ADVERTISED_HOST
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    tty: true
  - name: mongo
    image: edenlabllc/alpine-mongo:4.0.1-0
    ports:
    - containerPort: 27017
    tty: true
    resources:
      requests:
        memory: "64Mi"
        cpu: "50m"
      limits:
        memory: "256Mi"
        cpu: "300m"
  - name: redis
    image: redis:4.0-alpine3.9
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 200m
        memory: 256Mi       
    ports:
    - containerPort: 6379 
    tty: true
  volumes:
  - name: docker-graph-storage 
    emptyDir: {} 
  nodeSelector:
    node: "$RD_CROP"     
"""
            }
          }
          steps {
            container(name: 'kafkazookeeper', shell: '/bin/sh') {
              sh '''
                sleep 15;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic medical_events --partitions 1 --replication-factor 1;
                sleep 5;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic person_events --partitions 1 --replication-factor 1;
                sleep 5;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic mongo_events --partitions 1 --replication-factor 1
              '''
            }          
            container(name: 'docker', shell: '/bin/sh') {
              sh 'sed -i "s/travis/${POD_IP}/g" .env'
              sh 'echo -----Build Docker container for GraphQL-------'
              sh 'apk update && apk add --no-cache jq curl bash elixir git ncurses-libs zlib ca-certificates openssl make g++ erlang-crypto erlang-runtime-tools;'
              sh 'echo " ---- step: Build docker image ---- ";'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/build-container.sh -o build-container.sh; bash ./build-container.sh'
              sh 'echo " ---- step: Start docker container ---- ";'
              sh 'mix local.rebar --force'
              sh 'mix local.hex --force'
              sh 'mix deps.get'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/start-container.sh -o start-container.sh; bash ./start-container.sh'
              withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                sh 'echo " ---- step: Push docker image ---- ";'
                sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/push-changes.sh -o push-changes.sh; bash ./push-changes.sh'
              }
            }
          }
        }
        stage('Build audit-log-consumer') {
          environment {
            APPS='[{"app":"audit_log_consumer","chart":"medical-events-api","namespace":"me","deployment":"audit-log-consumer","label":"audit-log-consumer"}]'
            DOCKER_CREDENTIALS = 'credentials("20c2924a-6114-46dc-8e39-bfadd1cf8acf")'
          }
          agent {
            kubernetes {
              label "audit-log-consumer-$BUILD_ID-$NAME"
              defaultContainer 'jnlp'
              yaml """
apiVersion: v1
kind: Pod
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "$RD_CROP"
    effect: "NoSchedule"
  containers:
  - name: docker
    image: edenlabllc/docker:18.09-alpine-elixir-1.8.1
    resources:
      limits:
        memory: 512Mi
      requests:
        cpu: 500m
        memory: 128Mi
    env:
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: DOCKER_HOST 
      value: tcp://localhost:2375           
    command:
    - cat
    tty: true
  - name: dind
    image: docker:18.09.2-dind
    resources:
      limits:
        memory: 2048Mi
      requests:
        cpu: 200m
        memory: 256Mi      
    securityContext: 
        privileged: true 
    ports:
    - containerPort: 2375
    tty: true
    volumeMounts: 
    - name: docker-graph-storage 
      mountPath: /var/lib/docker        
  - name: kafkazookeeper
    image: edenlabllc/kafka-zookeeper:2.1.0
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 200m
        memory: 256Mi       
    ports:
    - containerPort: 2181
    - containerPort: 9092
    env:
    - name: ADVERTISED_HOST
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    tty: true
  - name: mongo
    image: edenlabllc/alpine-mongo:4.0.1-0
    ports:
    - containerPort: 27017
    tty: true
    resources:
      requests:
        memory: "64Mi"
        cpu: "50m"
      limits:
        memory: "256Mi"
        cpu: "300m"
  - name: redis
    image: redis:4.0-alpine3.9
    resources:
      limits:
        memory: 128Mi
      requests:
        cpu: 200m
        memory: 32Mi     
    ports:
    - containerPort: 6379 
    tty: true
  volumes:
  - name: docker-graph-storage 
    emptyDir: {}
  nodeSelector:
    node: "$RD_CROP"  
"""
            }
          }
          steps {
            container(name: 'kafkazookeeper', shell: '/bin/sh') {
              sh '''
                sleep 15;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic medical_events --partitions 1 --replication-factor 1;
                sleep 5;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic person_events --partitions 1 --replication-factor 1;
                sleep 5;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic mongo_events --partitions 1 --replication-factor 1
              '''
            }          
            container(name: 'docker', shell: '/bin/sh') {
              sh 'sed -i "s/travis/${POD_IP}/g" .env'
              sh 'echo -----Build Docker container for MergeLegalEntities consumer-------'
              sh 'apk update && apk add --no-cache jq curl bash elixir git ncurses-libs zlib ca-certificates openssl make g++ erlang-crypto erlang-runtime-tools;'
              sh 'echo " ---- step: Build docker image ---- ";'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/build-container.sh -o build-container.sh; bash ./build-container.sh'
              sh 'echo " ---- step: Start docker container ---- ";'
              sh 'mix local.rebar --force'
              sh 'mix local.hex --force'
              sh 'mix deps.get'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/start-container.sh -o start-container.sh; bash ./start-container.sh'
              withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                sh 'echo " ---- step: Push docker image ---- ";'
                sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/push-changes.sh -o push-changes.sh; bash ./push-changes.sh'
              }
            }
          }
        }
        stage('Build Number generator') {
          environment {
            APPS='[{"app":"number_generator","chart":"medical-events-api","namespace":"me","deployment":"number-generator","label":"number-generator"}]'
            DOCKER_CREDENTIALS = 'credentials("20c2924a-6114-46dc-8e39-bfadd1cf8acf")'
          }
          agent {
            kubernetes {
              label "number-generator-$BUILD_ID-$NAME"
              defaultContainer 'jnlp'
              yaml """
apiVersion: v1
kind: Pod
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "$RD_CROP"
    effect: "NoSchedule"
  containers:
  - name: docker
    image: edenlabllc/docker:18.09-alpine-elixir-1.8.1
    resources:
      limits:
        memory: 512Mi
      requests:
        cpu: 500m
        memory: 128Mi     
    env:
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: DOCKER_HOST 
      value: tcp://localhost:2375           
    command:
    - cat
    tty: true
  - name: dind
    image: docker:18.09.2-dind
    resources:
      limits:
        memory: 2048Mi
      requests:
        cpu: 200m
        memory: 256Mi      
    securityContext: 
        privileged: true 
    ports:
    - containerPort: 2375
    tty: true
    volumeMounts: 
    - name: docker-graph-storage 
      mountPath: /var/lib/docker        
  - name: kafkazookeeper
    image: edenlabllc/kafka-zookeeper:2.1.0
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 200m
        memory: 256Mi       
    ports:
    - containerPort: 2181
    - containerPort: 9092
    env:
    - name: ADVERTISED_HOST
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    tty: true
  - name: redis
    image: redis:4.0-alpine3.9
    resources:
      limits:
        memory: 128Mi
      requests:
        cpu: 200m
        memory: 32Mi    
    ports:
    - containerPort: 6379 
    tty: true
  volumes:
  - name: docker-graph-storage 
    emptyDir: {}
  nodeSelector:
    node: "$RD_CROP"    
"""
            }
          }
          steps {
            container(name: 'kafkazookeeper', shell: '/bin/sh') {
              sh '''
                sleep 15;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic medical_events --partitions 1 --replication-factor 1;
                sleep 5;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic person_events --partitions 1 --replication-factor 1;
                sleep 5;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic mongo_events --partitions 1 --replication-factor 1
              '''
            }          
            container(name: 'docker', shell: '/bin/sh') {
              sh 'sed -i "s/travis/${POD_IP}/g" .env'
              sh 'echo -----Build Docker container for Scheduler-------'
              sh 'apk update && apk add --no-cache jq curl bash elixir git ncurses-libs zlib ca-certificates openssl make g++ erlang-crypto erlang-runtime-tools;'
              sh 'echo " ---- step: Build docker image ---- ";'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/build-container.sh -o build-container.sh; bash ./build-container.sh'
              sh 'echo " ---- step: Start docker container ---- ";'
              sh 'mix local.rebar --force'
              sh 'mix local.hex --force'
              sh 'mix deps.get'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/start-container.sh -o start-container.sh; bash ./start-container.sh'
              withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                sh 'echo " ---- step: Push docker image ---- ";'
                sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/push-changes.sh -o push-changes.sh; bash ./push-changes.sh'
              }
            }
          }
        }
      }
    }
    stage ('Deploy') {
      when {
        allOf {
            environment name: 'CHANGE_ID', value: ''
            branch 'develop'
        }
      }
      environment {
        APPS='[{"app":"medical_events_api","chart":"medical-events-api","namespace":"me","deployment":"api-medical-events","label":"api-medical-events"},{"app":"event_consumer","chart":"medical-events-api","namespace":"me","deployment":"event-consumer","label":"event-consumer"},{"app":"person_consumer","chart":"medical-events-api","namespace":"me","deployment":"person-consumer","label":"person-consumer"},{"app":"audit_log_consumer","chart":"medical-events-api","namespace":"me","deployment":"audit-log-consumer","label":"audit-log-consumer"},{"app":"number_generator","chart":"medical-events-api","namespace":"me","deployment":"number-generator","label":"number-generator"}]'
      }
      agent {
        kubernetes {
          label "me-deploy-$BUILD_ID-$NAME"
          defaultContainer 'jnlp'
          yaml """
apiVersion: v1
kind: Pod
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "$RD_CROP"
    effect: "NoSchedule"
  containers:
  - name: kubectl
    image: edenlabllc/k8s-kubectl:v1.13.2
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 200m
        memory: 256Mi       
    command:
    - cat
    tty: true
  nodeSelector:
    node: "$RD_CROP"
"""
        }
      }
      steps {
        container(name: 'kubectl', shell: '/bin/sh') {
          sh 'apk add curl bash jq'
          sh 'echo " ---- step: Deploy to cluster ---- ";'
          sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/autodeploy.sh -o autodeploy.sh; bash ./autodeploy.sh'
        }
      }
    }
    
  }
  post { 
    success {
      slackSend (color: 'good', message: "Build <${RUN_CHANGES_DISPLAY_URL[0..-8]}status|#$BUILD_NUMBER> of ${JOB_NAME} passed in ${currentBuild.durationString}")
    }
    failure {
      slackSend (color: 'danger', message: "Build <${RUN_CHANGES_DISPLAY_URL[0..-8]}status|#$BUILD_NUMBER> of ${JOB_NAME} failed in ${currentBuild.durationString}")
    }
    aborted {
      slackSend (color: 'warning', message: "Build <${RUN_CHANGES_DISPLAY_URL[0..-8]}status|#$BUILD_NUMBER> of ${JOB_NAME} canceled in ${currentBuild.durationString}")
    }
    always {
      node('delete-instance') {    
        container(name: 'gcloud', shell: '/bin/sh') {
          withCredentials([file(credentialsId: 'e7e3e6df-8ef5-4738-a4d5-f56bb02a8bb2', variable: 'KEYFILE')]) {
            sh 'apk update && apk add curl bash git'
            sh 'gcloud auth activate-service-account jenkins-pool@ehealth-162117.iam.gserviceaccount.com --key-file=${KEYFILE} --project=ehealth-162117'
            sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/delete_instance.sh -o delete_instance.sh; bash ./delete_instance.sh'
          }
          slackSend (color: '#4286F5', message: "Stage for deleting instance for job <${RUN_CHANGES_DISPLAY_URL[0..-8]}status|#$BUILD_NUMBER> passed")
        }
      }
    }
  }
}

