alias k='kubectl'
alias ka='kubectl apply -f'
alias kc='kubectl create'
alias kd='kubectl describe'
alias kg='kubectl get'
alias kgp='kubectl get pod'
alias kgpa='kubectl get pod -A'
alias ke='kubectl explain'
alias kl='kubectl logs'
alias kla='kubectl logs --all-containers'
alias kt='kubectl tree'
alias kdel='kubectl delete'
alias kapi='kubectl api-resources'
alias t='tanzu'
alias tpi='tanzu package installed'
alias tpil='tanzu package installed list'
alias tpila='tanzu package installed list -A'
alias tmc="tanzu mission-control"

alias gb='git branch'
alias gc='git checkout'
alias gs="git status"
alias gp="git push"

alias tree="tree -a -I '.git'"
alias ssh-fix='eval `ssh-agent` ; ssh-add ~/.ssh/git_key'

alias kns=kubens
alias kx=kubectx

alias derek='ssh matt@192.168.0.3'

alias pssh="parallel-ssh  -h hosts -i"

alias obe='eval "$(om bosh-env)"'

alias ll='ls -la'

alias vccd='vcc download -m /home/matt/minio/vmware-products/vmd-manifest.yml --accepteula -o /home/matt/minio/vmware-products'

alias tkgs-nsxt-on='ansible-playbook /home/matt/workspace/projects/vmware-lab-builder/deploy.yml --extra-vars "@./var-examples/tanzu/vsphere-nsxt/opinionated-1host.yml"'
alias tkgs-nsxt-off='ansible-playbook /home/matt/workspace/projects/vmware-lab-builder/destroy.yml --extra-vars "@./var-examples/tanzu/vsphere-nsxt/opinionated-1host.yml"'
alias tkgs-avi-on='ansible-playbook /home/matt/workspace/projects/vmware-lab-builder/deploy.yml --extra-vars "@./var-examples/tanzu/vsphere-vds-alb/opinionated-1host.yml"'
alias tkgs-avi-off='ansible-playbook /home/matt/workspace/projects/vmware-lab-builder/destroy.yml --extra-vars "@./var-examples/tanzu/vsphere-vds-alb/opinionated-1host.yml"'
alias tkgm-on='ansible-playbook /home/matt/workspace/projects/vmware-lab-builder/deploy.yml --extra-vars "@./var-examples/tanzu/multi-cloud/opinionated-1host.yml"'
alias tkgm-off='ansible-playbook /home/matt/workspace/projects/vmware-lab-builder/destroy.yml --extra-vars "@./var-examples/tanzu/multi-cloud/opinionated-1host.yml"'

alias au='sudo apt update && sudo apt upgrade'