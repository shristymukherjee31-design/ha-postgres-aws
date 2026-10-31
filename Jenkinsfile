// One pipeline for the whole lifecycle.
// deploy   : Terraform, Ansible, PostgreSQL and cluster verification
// failover : Fence old primary, promote standby and update DNS
// destroy  : Destroy AWS infrastructure

pipeline {
  agent any

  parameters {
    choice(
      name: 'ACTION',
      choices: ['deploy', 'failover', 'destroy'],
      description: 'Which lifecycle action to run'
    )

    booleanParam(
      name: 'AUTO_APPROVE',
      defaultValue: false,
      description: 'Skip manual approval stages'
    )

    booleanParam(
      name: 'FORCE',
      defaultValue: false,
      description: 'Failover only: proceed even if primary responds'
    )
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 40, unit: 'MINUTES')
  }

  environment {
    REPO_DIR         = '/home/shristy/ha-postgres-aws'
    FORCE            = "${params.FORCE ? '1' : '0'}"
    TF_IN_AUTOMATION = 'true'
  }

  stages {

    // ------------------------- COMMON CHECKS -------------------------

    stage('Check Prerequisites') {
      steps {
        script {
          currentBuild.description = params.ACTION
        }

        dir(env.REPO_DIR) {
          sh '''#!/bin/bash
set -u

missing=0

for tool in terraform ansible-playbook aws ssh; do
  if command -v "$tool" > /dev/null; then
    echo "OK       $tool"
  else
    echo "MISSING  $tool"
    missing=1
  fi
done

for f in terraform.tfvars ansible/group_vars/all/secrets.yml; do
  if [ -f "$f" ]; then
    echo "OK       $f"
  else
    echo "MISSING  $f"
    missing=1
  fi
done

exit $missing
'''
        }
      }
    }

    stage('Verify AWS Credentials') {
      steps {
        sh 'aws sts get-caller-identity --output text --query "[Account,Arn]"'
      }
    }

    // ------------------------- UPDATE MY IP -------------------------

    stage('Detect and Allow My IP') {
      when {
        expression { return params.ACTION != 'destroy' }
      }

      steps {
        dir(env.REPO_DIR) {
          sh './scripts/allow_my_ip.sh'

          script {
            def ip = sh(
              script: '''awk -F'"' '/^my_ip/ {print $2}' terraform.tfvars''',
              returnStdout: true
            ).trim()

            currentBuild.description = "${params.ACTION} | allowed IP ${ip}"
          }
        }
      }
    }

    // ------------------------- TERRAFORM -------------------------

    stage('Terraform Init') {
      when {
        expression { return params.ACTION != 'failover' }
      }

      steps {
        dir("${env.REPO_DIR}/terraform") {
          sh 'terraform init -input=false -no-color'
        }
      }
    }

    stage('Terraform Validate') {
      when {
        expression { return params.ACTION == 'deploy' }
      }

      steps {
        dir("${env.REPO_DIR}/terraform") {
          sh 'terraform validate -no-color'
        }
      }
    }

    stage('Terraform Plan') {
      when {
        expression { return params.ACTION == 'deploy' }
      }

      steps {
        dir("${env.REPO_DIR}/terraform") {
          sh 'terraform plan -input=false -no-color -var-file=../terraform.tfvars -out=tfplan'
        }
      }
    }

    stage('Approve Infrastructure') {
      when {
        expression {
          return params.ACTION == 'deploy' && !params.AUTO_APPROVE
        }
      }

      steps {
        input message: 'Review the Terraform plan in the console. Apply it?',
              ok: 'Apply'
      }
    }

    stage('Terraform Apply') {
      when {
        expression { return params.ACTION == 'deploy' }
      }

      steps {
        dir("${env.REPO_DIR}/terraform") {
          sh 'terraform apply -input=false -no-color tfplan'
        }
      }
    }

    // ------------------------- ANSIBLE -------------------------

    stage('Refresh Inventory') {
      when {
        expression { return params.ACTION == 'deploy' }
      }

      steps {
        dir("${env.REPO_DIR}/ansible") {
          sh '''#!/bin/bash
set -e

test -s ~/.ssh/ha-pg.conf

grep -E '^Host (bastion|primary|standby)$' ~/.ssh/ha-pg.conf

ansible-inventory --graph
'''
        }
      }
    }

    stage('Test SSH Connectivity') {
      when {
        expression { return params.ACTION == 'deploy' }
      }

      steps {
        sh '''#!/bin/bash
set -u

for host in bastion primary standby; do
  ok=0

  for i in $(seq 1 30); do
    if ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" true 2>/dev/null; then
      ok=1
      break
    fi

    echo "Waiting for SSH on $host ($i/30)"
    sleep 10
  done

  if [ "$ok" != "1" ]; then
    echo "SSH to $host did not become ready"
    exit 1
  fi
done

echo "SSH is ready on all hosts"
'''

        dir("${env.REPO_DIR}/ansible") {
          sh 'ansible all -m ping'
        }
      }
    }

    stage('Deploy PostgreSQL and Replication') {
      when {
        expression { return params.ACTION == 'deploy' }
      }

      steps {
        dir("${env.REPO_DIR}/ansible") {
          sh 'ansible-playbook site.yml'
        }
      }
    }

    stage('Verify Cluster') {
      when {
        expression { return params.ACTION == 'deploy' }
      }

      steps {
        dir(env.REPO_DIR) {
          sh './tests/verify_cluster.sh'
        }
      }
    }

    // ------------------------- FAILOVER -------------------------

    stage('Check Primary Down') {
      when {
        expression { return params.ACTION == 'failover' }
      }

      steps {
        dir(env.REPO_DIR) {
          sh './scripts/check_primary.sh'
        }
      }
    }

    stage('Fence Primary') {
      when {
        expression { return params.ACTION == 'failover' }
      }

      steps {
        dir(env.REPO_DIR) {
          sh './scripts/fence_primary.sh'
        }
      }
    }

    stage('Promote Standby') {
      when {
        expression { return params.ACTION == 'failover' }
      }

      steps {
        dir(env.REPO_DIR) {
          sh './scripts/promote_standby.sh'
        }
      }
    }

    stage('Update DNS') {
      when {
        expression { return params.ACTION == 'failover' }
      }

      steps {
        dir(env.REPO_DIR) {
          sh './scripts/update_dns.sh'
        }
      }
    }

    stage('Verify Failover') {
      when {
        expression { return params.ACTION == 'failover' }
      }

      steps {
        dir("${env.REPO_DIR}/terraform") {
          sh '''#!/bin/bash
set -u

EXPECTED=$(terraform output -raw standby_private_ip)

GOT=""

for i in $(seq 1 6); do
  GOT=$(ssh -o BatchMode=yes -o ConnectTimeout=10 bastion "getent hosts db.internal" | awk '{print $1}')

  [ "$GOT" = "$EXPECTED" ] && break

  sleep 5
done

if [ "$GOT" != "$EXPECTED" ]; then
  echo "FAIL: db.internal resolves to '$GOT', expected $EXPECTED"
  exit 1
fi

echo "db.internal -> $GOT (the promoted standby)"

RECOVERY=$(ssh -o BatchMode=yes -o ConnectTimeout=10 standby 'sudo -u postgres psql -tAc "SELECT pg_is_in_recovery();"')

if [ "$RECOVERY" != "f" ]; then
  echo "FAIL: the new primary is still in recovery mode"
  exit 1
fi

echo "The new primary is writable (pg_is_in_recovery = f)."
'''
        }
      }
    }

    // ------------------------- DESTROY -------------------------

    stage('Approve Destroy') {
      when {
        expression {
          return params.ACTION == 'destroy' && !params.AUTO_APPROVE
        }
      }

      steps {
        input message: 'Destroy ALL infrastructure (VPC, EC2, NAT, DNS)?',
              ok: 'Destroy'
      }
    }

    stage('Terraform Destroy') {
      when {
        expression { return params.ACTION == 'destroy' }
      }

      steps {
        dir("${env.REPO_DIR}/terraform") {
          sh 'terraform destroy -auto-approve -input=false -no-color -var-file=../terraform.tfvars'
        }
      }
    }

    stage('Verify Clean') {
      when {
        expression { return params.ACTION == 'destroy' }
      }

      steps {
        dir("${env.REPO_DIR}/terraform") {
          sh '''#!/bin/bash
if [ -n "$(terraform state list)" ]; then
  echo "Resources are still in the Terraform state"
  exit 1
fi

echo "Terraform state is empty: all infrastructure destroyed."
'''
        }
      }
    }
  }
}
