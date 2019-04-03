def author() {
  return sh(returnStdout: true, script: 'git log -n 1 --format="%an"').trim()
}
pipeline {
  agent {
    node { 
      label 'ehealth-build-big' 
      }
  }
  environment {
    PROJECT_NAME = 'medical-events'
    MIX_ENV = 'test'
    DOCKER_NAMESPACE = 'edenlabllc'
    POSTGRES_VERSION = '10'
    POSTGRES_USER = 'postgres'
    POSTGRES_PASSWORD = 'postgres'
    POSTGRES_DB = 'postgres'
    NO_ECTO_SETUP = 'true'
  }
  stages {
    stage('Init') {
      options {
        timeout(activity: true, time: 3)
      }
      steps {
        sh 'cat /etc/hostname'
        sh 'sudo docker rm -f $(sudo docker ps -a -q) || true'
        sh 'sudo docker rmi $(sudo docker images -q) || true'
        sh 'sudo docker system prune -f'
        sh '''
          sudo docker run -d --name postgres -p 5432:5432 edenlabllc/alpine-postgre:pglogical-gis-1.1;
          sudo docker run -d --name mongo -p 27017:27017 edenlabllc/alpine-mongo:4.0.1-0;
          sudo docker run -d --name redis -p 6379:6379 redis:4-alpine3.9;
          sudo docker run -d --name kafkazookeeper -p 2181:2181 -p 9092:9092 edenlabllc/kafka-zookeeper:2.1.0;
          sudo docker ps;
        '''
        sh '''
          until psql -U postgres -h localhost -c "create database ehealth";
            do
              sleep 2
            done
          psql -U postgres -h localhost -c "create database prm_dev";
          psql -U postgres -h localhost -c "create database fraud_dev";
          psql -U postgres -h localhost -c "create database event_manager_dev";
        '''
        sh '''
          until sudo docker exec -i kafkazookeeper /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic medical_events;
            do
              sleep 2
            done
          sudo docker exec -i kafkazookeeper /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic person_events;
          sudo docker exec -i kafkazookeeper /opt/kafka_2.12-2.1.0/bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic mongo_events;
        '''
        sh '''
          mix local.hex --force;
          mix local.rebar --force;
          mix deps.get;
          mix deps.compile;
        '''
      }
    }
    stage('Test') {
      options {
        timeout(activity: true, time: 3)
      }
      steps {
        sh '''
          (curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/tests.sh -o tests.sh; chmod +x ./tests.sh; ./tests.sh) || exit 1;
          '''
      }
    }
    stage('Build') {
//      failFast true
      parallel {
        stage('Build medical-events-app') {
          options {
            timeout(activity: true, time: 3)
          }
          environment {
            APPS='[{"app":"medical_events_api","chart":"medical-events-api","namespace":"me","deployment":"api-medical-events","label":"api-medical-events"}]'
          }
          steps {
            sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/build-container.sh -o build-container.sh;
              chmod +x ./build-container.sh;
              ./build-container.sh;  
            '''
          }
        }
        stage('Build event-consumer-app') {
          options {
            timeout(activity: true, time: 3)
          }
          environment {
            APPS='[{"app":"event_consumer","chart":"medical-events-api","namespace":"me","deployment":"event-consumer","label":"event-consumer"}]'
          }
          steps {
            sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/build-container.sh -o build-container.sh;
              chmod +x ./build-container.sh;
              ./build-container.sh;  
            '''
          }
        }
        stage('Build person-consumer-app') {
          options {
            timeout(activity: true, time: 3)
          }
          environment {
            APPS='[{"app":"person_consumer","chart":"medical-events-api","namespace":"me","deployment":"person-consumer","label":"person-consumer"}]'
          }
          steps {
            sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/build-container.sh -o build-container.sh;
              chmod +x ./build-container.sh;
              ./build-container.sh;
            '''
          }
        }
        stage('Build audit-log-consumer-app') {
          options {
            timeout(activity: true, time: 3)
          }
          environment {
            APPS='[{"app":"audit_log_consumer","chart":"medical-events-api","namespace":"me","deployment":"audit-log-consumer","label":"audit-log-consumer"}]'
          }
          steps {
            sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/build-container.sh -o build-container.sh;
              chmod +x ./build-container.sh;
              ./build-container.sh;
            '''
          }
        }
        stage('Build number-generator-app') {
          options {
            timeout(activity: true, time: 3)
          }
          environment {
            APPS='[{"app":"number_generator","chart":"medical-events-api","namespace":"me","deployment":"number-generator","label":"number-generator"}]'
          }
          steps {
            sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/build-container.sh -o build-container.sh;
              chmod +x ./build-container.sh;
              ./build-container.sh; 
            '''
          }
        }
        stage('Build medical-events-scheduler-app') {
          options {
            timeout(activity: true, time: 3)
          }
          environment {
            APPS='[{"app":"medical_events_scheduler","chart":"medical-events-api","namespace":"me","deployment":"medical-events-scheduler","label":"medical-events-scheduler"}]'
          }
          steps {
            sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/build-container.sh -o build-container.sh;
              chmod +x ./build-container.sh;
              ./build-container.sh;
            '''
          }
        }
      }
    }
    stage('Run medical-events-app and push') {
      options {
        timeout(activity: true, time: 3)
      }
      environment {
        APPS='[{"app":"medical_events_api","chart":"medical-events-api","namespace":"me","deployment":"api-medical-events","label":"api-medical-events"}]'
      }
      steps {
        sh '''
          curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/start-container.sh -o start-container.sh;
          chmod +x ./start-container.sh; 
          ./start-container.sh;
        '''
        withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
          sh 'echo " ---- step: Push docker image ---- ";'
          sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/push-changes.sh -o push-changes.sh;
              chmod +x ./push-changes.sh;
              ./push-changes.sh
            '''
        }
      }
    }
    stage('Run event-consumer-app and push') {
      options {
        timeout(activity: true, time: 3)
      }
      environment {
        APPS='[{"app":"event_consumer","chart":"medical-events-api","namespace":"me","deployment":"event-consumer","label":"event-consumer"}]'
      }
      steps {
        sh '''
          curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/start-container.sh -o start-container.sh;
          chmod +x ./start-container.sh; 
          ./start-container.sh;
        '''
        withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
          sh 'echo " ---- step: Push docker image ---- ";'
          sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/push-changes.sh -o push-changes.sh;
              chmod +x ./push-changes.sh;
              ./push-changes.sh
            '''
        }
      }
    }
    stage('Run person-consumer-app and push') {
      options {
        timeout(activity: true, time: 3)
      }
      environment {
        APPS='[{"app":"person_consumer","chart":"medical-events-api","namespace":"me","deployment":"person-consumer","label":"person-consumer"}]'
      }
      steps {
        sh '''
          curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/start-container.sh -o start-container.sh;
          chmod +x ./start-container.sh; 
          ./start-container.sh;
        '''
        withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
          sh 'echo " ---- step: Push docker image ---- ";'
          sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/push-changes.sh -o push-changes.sh;
              chmod +x ./push-changes.sh;
              ./push-changes.sh
            '''
        }
      }
    }
    stage('Run audit-log-consumer-app and push') {
      options {
        timeout(activity: true, time: 3)
      }
      environment {
        APPS='[{"app":"audit_log_consumer","chart":"medical-events-api","namespace":"me","deployment":"audit-log-consumer","label":"audit-log-consumer"}]'
      }
      steps {
        sh '''
          curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/start-container.sh -o start-container.sh;
          chmod +x ./start-container.sh; 
          ./start-container.sh;
        '''
        withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
          sh 'echo " ---- step: Push docker image ---- ";'
          sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/push-changes.sh -o push-changes.sh;
              chmod +x ./push-changes.sh;
              ./push-changes.sh
            '''
        }
      }
    }
    stage('Run number-generator-app and push') {
      options {
        timeout(activity: true, time: 3)
      }
      environment {
        APPS='[{"app":"number_generator","chart":"medical-events-api","namespace":"me","deployment":"number-generator","label":"number-generator"}]'
      }
      steps {
        sh '''
          curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/start-container.sh -o start-container.sh;
          chmod +x ./start-container.sh; 
          ./start-container.sh;
        '''
        withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
          sh 'echo " ---- step: Push docker image ---- ";'
          sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/push-changes.sh -o push-changes.sh;
              chmod +x ./push-changes.sh;
              ./push-changes.sh
            '''
        }
      }
    }
    stage('Run medical-events-scheduler-app and push') {
      options {
        timeout(activity: true, time: 3)
      }
      environment {
        APPS='[{"app":"medical_events_scheduler","chart":"medical-events-api","namespace":"me","deployment":"medical-events-scheduler","label":"medical-events-scheduler"}]'
      }
      steps {
        sh '''
          curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/start-container.sh -o start-container.sh;
          chmod +x ./start-container.sh; 
          ./start-container.sh;
        '''
        withCredentials(bindings: [usernamePassword(credentialsId: '8232c368-d5f5-4062-b1e0-20ec13b0d47b', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
          sh 'echo " ---- step: Push docker image ---- ";'
          sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/push-changes.sh -o push-changes.sh;
              chmod +x ./push-changes.sh;
              ./push-changes.sh
            '''
        }
      }
    }
    stage('Deploy') {
      options {
        timeout(activity: true, time: 3)
      }
      environment {
        APPS = '[{"app":"medical_events_api","chart":"medical-events-api","namespace":"me","deployment":"api-medical-events","label":"api-medical-events"},{"app":"event_consumer","chart":"medical-events-api","namespace":"me","deployment":"event-consumer","label":"event-consumer"},{"app":"person_consumer","chart":"medical-events-api","namespace":"me","deployment":"person-consumer","label":"person-consumer"},{"app":"audit_log_consumer","chart":"medical-events-api","namespace":"me","deployment":"audit-log-consumer","label":"audit-log-consumer"},{"app":"number_generator","chart":"medical-events-api","namespace":"me","deployment":"number-generator","label":"number-generator"},{"app":"medical_events_scheduler","chart":"medical-events-api","namespace":"me","deployment":"medical-events-scheduler","label":"medical-events-scheduler"}]'
      }
      steps {
        withCredentials([string(credentialsId: '86a8df0b-edef-418f-844a-cd1fa2cf813d', variable: 'GITHUB_TOKEN')]) {
          withCredentials([file(credentialsId: '091bd05c-0219-4164-8a17-777f4caf7481', variable: 'GCLOUD_KEY')]) {
            sh '''
              curl -s https://raw.githubusercontent.com/edenlabllc/ci-utils/umbrella_jenkins_gce/autodeploy.sh -o autodeploy.sh;
              chmod +x ./autodeploy.sh;
              ./autodeploy.sh
            '''
          }
        }
      }
    }
  }
  post {
    success {
      script {
        if (env.CHANGE_ID == null) {
          slackSend (color: 'good', message: "Build <${env.RUN_DISPLAY_URL}|#${env.BUILD_NUMBER}> (<https://github.com/edenlabllc/ehealth.api/commit/${env.GIT_COMMIT}|${env.GIT_COMMIT.take(7)}>) of ${env.JOB_NAME} by ${author()} *success* in ${currentBuild.durationString.replace(' and counting', '')}")
        } else if (env.BRANCH_NAME.startsWith('PR')) {
          slackSend (color: 'good', message: "Build <${env.RUN_DISPLAY_URL}|#${env.BUILD_NUMBER}> (<https://github.com/edenlabllc/ehealth.api/pull/${env.CHANGE_ID}|${env.GIT_COMMIT.take(7)}>) of ${env.JOB_NAME} in PR #${env.CHANGE_ID} by ${author()} *success* in ${currentBuild.durationString.replace(' and counting', '')}")
        }
      }
    }
    failure {
      script {
        if (env.CHANGE_ID == null) {
          slackSend (color: 'danger', message: "Build <${env.RUN_DISPLAY_URL}|#${env.BUILD_NUMBER}> (<https://github.com/edenlabllc/ehealth.api/commit/${env.GIT_COMMIT}|${env.GIT_COMMIT.take(7)}>) of ${env.JOB_NAME} by ${author()} *failed* in ${currentBuild.durationString.replace(' and counting', '')}")
        } else if (env.BRANCH_NAME.startsWith('PR')) {
          slackSend (color: 'danger', message: "Build <${env.RUN_DISPLAY_URL}|#${env.BUILD_NUMBER}> (<https://github.com/edenlabllc/ehealth.api/pull/${env.CHANGE_ID}|${env.GIT_COMMIT.take(7)}>) of ${env.JOB_NAME} in PR #${env.CHANGE_ID} by ${author()} *failed* in ${currentBuild.durationString.replace(' and counting', '')}")
        }
      }
    }
    aborted {
      script {
        if (env.CHANGE_ID == null) {
          slackSend (color: 'warning', message: "Build <${env.RUN_DISPLAY_URL}|#${env.BUILD_NUMBER}> (<https://github.com/edenlabllc/ehealth.api/commit/${env.GIT_COMMIT}|${env.GIT_COMMIT.take(7)}>) of ${env.JOB_NAME} by ${author()} *canceled* in ${currentBuild.durationString.replace(' and counting', '')}")
        } else if (env.BRANCH_NAME.startsWith('PR')) {
          slackSend (color: 'warning', message: "Build <${env.RUN_DISPLAY_URL}|#${env.BUILD_NUMBER}> (<https://github.com/edenlabllc/ehealth.api/pull/${env.CHANGE_ID}|${env.GIT_COMMIT.take(7)}>) of ${env.JOB_NAME} in PR #${env.CHANGE_ID} by ${author()} *canceled* in ${currentBuild.durationString.replace(' and counting', '')}")
        }
      }
    }
  }
}

