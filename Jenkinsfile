pipeline {
  agent none
    environment {
      PROJECT_NAME = 'medical-events'
      INSTANCE_TYPE = 'n1-highcpu-16'
}  
  stages {
    stage('Prepare instance') {
      agent {
        kubernetes {
          label 'create-instance'
          defaultContainer 'jnlp'
          instanceCap '4'          
        }
      }
      steps {
        container(name: 'gcloud', shell: '/bin/sh') {
          withCredentials([file(credentialsId: 'e7e3e6df-8ef5-4738-a4d5-f56bb02a8bb2', variable: 'KEYFILE')]) {
            sh 'apk update && apk add curl bash'
            sh 'gcloud auth activate-service-account jenkins-pool@ehealth-162117.iam.gserviceaccount.com --key-file=${KEYFILE} --project=ehealth-162117'
            sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/create_instance.sh -o create_instance.sh; bash ./create_instance.sh'
          }
          slackSend (color: '#8E24AA', message: "Instance for ${env.BUILD_TAG} created")
        }
      }
      post {
        success {
          slackSend (color: 'good', message: "Job - ${env.BUILD_TAG} STARTED (<${env.BUILD_URL}|Open>)")
        }
        failure {
          slackSend (color: 'danger', message: "Job - ${env.BUILD_TAG} FAILED to start (<${env.BUILD_URL}|Open>)")
        }
        aborted {
          slackSend (color: 'warning', message: "Job - ${env.BUILD_TAG} ABORTED before start (<${env.BUILD_URL}|Open>)")
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
          label 'medical-events-test'
          defaultContainer 'jnlp'
          yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    stage: test
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "${BUILD_TAG}"
    effect: "NoSchedule"
  containers:
  - name: elixir
    image: liubenokvlad/ubuntu18-otp-25-2-5-elixir:1.8.1
    command:
    - cat
    tty: true
  - name: mongo
    image: mvertes/alpine-mongo:4.0.1-0
    ports:
    - containerPort: 27017
    tty: true
  - name: redis
    image: redis:4-alpine3.9
    ports:
    - containerPort: 6379
    tty: true
  - name: kafkazookeeper
    image: johnnypark/kafka-zookeeper
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
    node: ${BUILD_TAG}
"""
            }
          }
          steps {
            container(name: 'kafkazookeeper', shell: '/bin/sh') {
              sh '''
                sleep 40;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic medical_events --partitions 1 --replication-factor 1
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic person_events --partitions 1 --replication-factor 1
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
                mix deps.update kaffe
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
        NO_ECTO_SETUP = 'True'
      }
    //  failFast true      
      parallel {
        stage('Build medical-events-api') {
          environment {
            APPS='[{"app":"medical_events_api","chart":"medical-events-api","namespace":"me","deployment":"api-medical-events","label":"api-medical-events"}]'
            DOCKER_CREDENTIALS = 'credentials("20c2924a-6114-46dc-8e39-bfadd1cf8acf")'
          }
          agent {
            kubernetes {
              label 'medical-events-api-build'
              defaultContainer 'jnlp'
              yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    stage: build
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "${BUILD_TAG}"
    effect: "NoSchedule"
  containers:
  - name: docker
    image: liubenokvlad/docker:18.09-alpine-elixir-1.8.1
    volumeMounts:
    - mountPath: /var/run/docker.sock
      name: volume
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
    image: johnnypark/kafka-zookeeper:2.1.0
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
    ports:
    - containerPort: 6379 
    tty: true
  nodeSelector:
    node: ${BUILD_TAG}
  volumes:
  - name: docker-graph-storage 
    emptyDir: {}  
  - name: volume
    hostPath:
      path: /var/run/docker.sock
"""
            }
          }
          steps {
            container(name: 'kafkazookeeper', shell: '/bin/sh') {
              sh '''
                sleep 70;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic medical_events --partitions 1 --replication-factor 1
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic person_events --partitions 1 --replication-factor 1
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic mongo_events --partitions 1 --replication-factor 1
              '''
            }          
            container(name: 'docker', shell: '/bin/sh') {
              sh 'sed -i "s/travis/${POD_IP}/g" .env'
              sh 'env'
              sh 'echo -----Build Docker container for EHealth API-------'
              sh 'apk update && apk add --no-cache jq curl bash elixir git ncurses-libs zlib ca-certificates openssl erlang-crypto  openssl make g++ erlang-runtime-tools;'
              sh 'echo " ---- step: Build docker image ---- ";'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/build-container.sh -o build-container.sh; bash ./build-container.sh'
              sh 'echo " ---- step: Start docker container ---- ";'
              sh 'mix local.rebar --force'
              sh 'mix local.hex --force'
              sh 'mix deps.get'
              sh 'sed -i "s|REDIS_URI=redis://travis:6379|REDIS_URI=redis://redis-master.redis.svc.cluster.local:6379|g" .env'
              // sh 'sed -i "s|MONGO_DB_URL=mongodb://travis:27017/taskafka|MONGO_DB_URL=mongodb://$POD_IP:27017/taskafka?replicaSet=rs0&readPreference=primary|g" .env'
              sh 'sed -i "s/KAFKA_BROKERS=travis/KAFKA_BROKERS=$POD_IP/g" .env'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/start-container.sh -o start-container.sh; bash ./start-container.sh'
              withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                sh 'echo " ---- step: Push docker image ---- ";'
                sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/push-changes.sh -o push-changes.sh; bash ./push-changes.sh'
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
              label 'event-consumer-build'
              defaultContainer 'jnlp'
              yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    stage: build
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "${BUILD_TAG}"
    effect: "NoSchedule"
  containers:
  - name: docker
    image: liubenokvlad/docker:18.09-alpine-elixir-1.8.1
    volumeMounts:
    - mountPath: /var/run/docker.sock
      name: volume
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
    image: johnnypark/kafka-zookeeper:2.1.0
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
    ports:
    - containerPort: 6379 
    tty: true     
  - name: dind
    image: docker:18.09.2-dind
    securityContext: 
        privileged: true 
    ports:
    - containerPort: 2375
    tty: true
    volumeMounts: 
    - name: docker-graph-storage 
      mountPath: /var/lib/docker            
  nodeSelector:
    node: ${BUILD_TAG}
  volumes:
  - name: volume
    hostPath:
      path: /var/run/docker.sock
  - name: docker-graph-storage 
    emptyDir: {}      
"""
            }
          }
          steps {
            container(name: 'kafkazookeeper', shell: '/bin/sh') {
              sh '''
                sleep 70;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic medical_events --partitions 1 --replication-factor 1
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic person_events --partitions 1 --replication-factor 1
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic mongo_events --partitions 1 --replication-factor 1
              '''
            }          
            container(name: 'docker', shell: '/bin/sh') {
              sh 'sed -i "s/travis/${POD_IP}/g" .env'
              sh 'echo -----Build Docker container for Casher-------'
              sh 'apk update && apk add --no-cache jq curl bash elixir git ncurses-libs zlib ca-certificates openssl make g++ erlang-crypto erlang-runtime-tools;'
              sh 'echo " ---- step: Build docker image ---- ";'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/build-container.sh -o build-container.sh; bash ./build-container.sh'
              sh 'echo " ---- step: Start docker container ---- ";'
              sh 'mix local.rebar --force'
              sh 'mix local.hex --force'
              sh 'mix deps.get'
              // sh 'sed -i "s|REDIS_URI=redis://travis:6379|REDIS_URI=redis://redis-master.redis.svc.cluster.local:6379|g" .env'
              // sh 'sed -i "s|MONGO_DB_URL=mongodb://travis:27017/taskafka|MONGO_DB_URL=mongodb://me-db-mongodb-replicaset.me-db.svc.cluster.local:27017/taskafka?replicaSet=rs0&readPreference=primary|g" .env'
              // sh 'sed -i "s/KAFKA_BROKERS=travis/KAFKA_BROKERS=$POD_IP/g" .env'
              sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/start-container.sh -o start-container.sh; bash ./start-container.sh'
              withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                sh 'echo " ---- step: Push docker image ---- ";'
                sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/push-changes.sh -o push-changes.sh; bash ./push-changes.sh'
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
              label 'person-consumer-build'
              defaultContainer 'jnlp'
              yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    stage: build
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "${BUILD_TAG}"
    effect: "NoSchedule"
  containers:
  - name: docker
    image: liubenokvlad/docker:18.09-alpine-elixir-1.8.1
    volumeMounts:
    - mountPath: /var/run/docker.sock
      name: volume
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
    securityContext: 
        privileged: true 
    ports:
    - containerPort: 2375
    tty: true
    volumeMounts: 
    - name: docker-graph-storage 
      mountPath: /var/lib/docker        
  - name: kafkazookeeper
    image: johnnypark/kafka-zookeeper:2.1.0
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
    ports:
    - containerPort: 6379 
    tty: true
  nodeSelector:
    node: ${BUILD_TAG}
  volumes:
  - name: volume
    hostPath:
      path: /var/run/docker.sock
  - name: docker-graph-storage 
    emptyDir: {}      
"""
            }
          }
          steps {
            container(name: 'kafkazookeeper', shell: '/bin/sh') {
              sh '''
                sleep 70;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic medical_events --partitions 1 --replication-factor 1
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic person_events --partitions 1 --replication-factor 1
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
              // sh 'sed -i "s|REDIS_URI=redis://travis:6379|REDIS_URI=redis://redis-master.redis.svc.cluster.local:6379|g" .env'
              // sh 'sed -i "s|MONGO_DB_URL=mongodb://travis:27017/taskafka|MONGO_DB_URL=mongodb://me-db-mongodb-replicaset.me-db.svc.cluster.local:27017/taskafka?replicaSet=rs0&readPreference=primary|g" .env'
              // sh 'sed -i "s/KAFKA_BROKERS=travis/KAFKA_BROKERS=$POD_IP/g" .env'
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
              label 'audit-log-consumer-build'
              defaultContainer 'jnlp'
              yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    stage: build
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "${BUILD_TAG}"
    effect: "NoSchedule"
  containers:
  - name: docker
    image: liubenokvlad/docker:18.09-alpine-elixir-1.8.1
    volumeMounts:
    - mountPath: /var/run/docker.sock
      name: volume
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
    securityContext: 
        privileged: true 
    ports:
    - containerPort: 2375
    tty: true
    volumeMounts: 
    - name: docker-graph-storage 
      mountPath: /var/lib/docker        
  - name: kafkazookeeper
    image: johnnypark/kafka-zookeeper:2.1.0
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
    ports:
    - containerPort: 6379 
    tty: true
  nodeSelector:
    node: ${BUILD_TAG}
  volumes:
  - name: volume
    hostPath:
      path: /var/run/docker.sock
  - name: docker-graph-storage 
    emptyDir: {}      
"""
            }
          }
          steps {
            container(name: 'kafkazookeeper', shell: '/bin/sh') {
              sh '''
                sleep 70;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic medical_events --partitions 1 --replication-factor 1
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic person_events --partitions 1 --replication-factor 1
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
              // sh 'sed -i "s|REDIS_URI=redis://travis:6379|REDIS_URI=redis://redis-master.redis.svc.cluster.local:6379|g" .env'
              // sh 'sed -i "s|MONGO_DB_URL=mongodb://travis:27017/taskafka|MONGO_DB_URL=mongodb://me-db-mongodb-replicaset.me-db.svc.cluster.local:27017/taskafka?replicaSet=rs0&readPreference=primary|g" .env'
              // sh 'sed -i "s/KAFKA_BROKERS=travis/KAFKA_BROKERS=$POD_IP/g" .env'
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
              label 'number-generator-build'
              defaultContainer 'jnlp'
              yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    stage: build
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "${BUILD_TAG}"
    effect: "NoSchedule"
  containers:
  - name: docker
    image: liubenokvlad/docker:18.09-alpine-elixir-1.8.1
    volumeMounts:
    - mountPath: /var/run/docker.sock
      name: volume
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
    securityContext: 
        privileged: true 
    ports:
    - containerPort: 2375
    tty: true
    volumeMounts: 
    - name: docker-graph-storage 
      mountPath: /var/lib/docker        
  - name: kafkazookeeper
    image: johnnypark/kafka-zookeeper:2.1.0
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
    ports:
    - containerPort: 6379 
    tty: true
  nodeSelector:
    node: ${BUILD_TAG}
  volumes:
  - name: volume
    hostPath:
      path: /var/run/docker.sock
  - name: docker-graph-storage 
    emptyDir: {}      
"""
            }
          }
          steps {
            container(name: 'kafkazookeeper', shell: '/bin/sh') {
              sh '''
                sleep 70;
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic medical_events --partitions 1 --replication-factor 1
                /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper 127.0.0.1:2181 --topic person_events --partitions 1 --replication-factor 1
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
              // sh 'sed -i "s|REDIS_URI=redis://travis:6379|REDIS_URI=redis://redis-master.redis.svc.cluster.local:6379|g" .env'
              // sh 'sed -i "s|MONGO_DB_URL=mongodb://travis:27017/taskafka|MONGO_DB_URL=mongodb://me-db-mongodb-replicaset.me-db.svc.cluster.local:27017/taskafka?replicaSet=rs0&readPreference=primary|g" .env'
              // sh 'sed -i "s/KAFKA_BROKERS=travis/KAFKA_BROKERS=$POD_IP/g" .env'
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
        APPS='[{"app":"medical_events_api","chart":"medical-events-api","namespace":"me","deployment":"api-medical-events","label":"api-medical-events"},{"app":"event_consumer","chart":"medical-events-api","namespace":"me","deployment":"event-consumer","label":"event-consumer"},{"app":"person_consumer","chart":"medical-events-api","namespace":"me","deployment":"person-consumer","label":"person-consumer"},{"app":"audit_log_consumer","chart":"medical-events-api","namespace":"me","deployment":"audit-log-consumer","label":"audit-log-consumer"},{"app":"secondary_events_consumer","chart":"medical-events-api","namespace":"me","deployment":"secondary-events-consumer","label":"secondary-events-consumer"},{"app":"number_generator","chart":"medical-events-api","namespace":"me","deployment":"number-generator","label":"number-generator"}]'
      }
      agent {
        kubernetes {
          label 'ehealth-deploy'
          defaultContainer 'jnlp'
          yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    stage: deploy
spec:
  tolerations:
  - key: "ci"
    operator: "Equal"
    value: "${BUILD_TAG}"
    effect: "NoSchedule"
  containers:
  - name: kubectl
    image: lachlanevenson/k8s-kubectl:v1.13.2
    command:
    - cat
    tty: true
  nodeSelector:
    node: ${BUILD_TAG}
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
      slackSend (color: 'good', message: "SUCCESSFUL: Job - ${env.JOB_NAME} ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open>) success in ${currentBuild.durationString}")
    }
    failure {
      slackSend (color: 'danger', message: "FAILED: Job - ${env.JOB_NAME} ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open>) failed in ${currentBuild.durationString}")
    }
    aborted {
      slackSend (color: 'warning', message: "ABORTED: Job - ${env.JOB_NAME} ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open>) canceled in ${currentBuild.durationString}")
    }
    always {
      node('delete-instance') {
        // checkout scm        
        container(name: 'gcloud', shell: '/bin/sh') {
          withCredentials([file(credentialsId: 'e7e3e6df-8ef5-4738-a4d5-f56bb02a8bb2', variable: 'KEYFILE')]) {
            checkout scm
            sh 'apk update && apk add curl bash git'
            sh 'gcloud auth activate-service-account jenkins-pool@ehealth-162117.iam.gserviceaccount.com --key-file=${KEYFILE} --project=ehealth-162117'
            sh 'curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins/delete_instance.sh -o delete_instance.sh; bash ./delete_instance.sh'
          }
          slackSend (color: '#4286F5', message: "Instance for ${env.BUILD_TAG} deleted")
        }
      }
    }
  }
}

