function sshp() {
  target=$1
  if [ -z $target ]; then
    >&2 echo "You must pass in a param. E.g. sshp root@1.2.3.4"
  fi
  ssh ${target} -o PreferredAuthentications=password -o PubkeyAuthentication=no
}

function asdfu() {
  product_name=${1:-}
  if [ -z $product_name ]; then
    >&2 echo "You must pass in a product name. E.g. asdfu kubectl"
    return 1
  fi

  product_version=${2:-}
  if [ -z $product_version ]; then
    product_version=latest
  fi

  asdf plugin add $product_name
  ret_code=$?
  if [ $ret_code -eq 2 ]; then
    asdf plugin update $product_name || return 1
  elif [ $ret_code -ne 2 ] && [ $ret_code -ne 0 ]; then
    >&2 echo "ERROR: Aborting"
    return 1
  fi

  asdf install $product_name $product_version
  if [ $? -ne 0 ]; then
    >&2 echo "ERROR: Aborting"
    return 1
  fi

  if [ "$product_version" == "latest" ]; then
    product_version="$(asdf list $product_name | sed 's/\*//g' | sort -r | head -n 1 | xargs)" || return 1
  fi
  echo "Setting ${product_version} as global default for ${product_name}"
  asdf global $product_name $product_version
}

function labon() {
  (
  # Ensure correct vars are set and error if not
  [ -z "${ESXI_IP:-}" ] && echo '$ESXI_IP must be set' && return 1
  [ -z "${ESXI_USERNAME:-}" ] && echo '$ESXI_USERNAME must be set' && return 1
  [ -z "${ESXI_PASSWORD:-}" ] && echo '$ESXI_PASSWORD must be set' && return 1
  unset GOVC_DATACENTER GOVC_HOST GOVC_DATASTORE GOVC_LIBRARY
  export GOVC_URL=$ESXI_IP
  export GOVC_USERNAME=$ESXI_USERNAME
  export GOVC_PASSWORD=$ESXI_PASSWORD
  export GOVC_INSECURE=true
  [ -z "${IPMI_IP:-}" ] && echo '$IPMI_IP must be set' && return 1
  [ -z "${IPMI_USERNAME:-}" ] && echo '$IPMI_USERNAME must be set' && return 1
  [ -z "${IPMI_PASSWORD:-}" ] && echo '$IPMI_PASSWORD must be set' && return 1

  if $(curl -k --output /dev/null --silent --head --fail -m 5 https://${GOVC_URL})
  then
      echo "Host is already online, exiting cleanly"
      return 0
  else
      echo "Host ${GOVC_URL} is not online, attempting to wake up"
  fi

  ipmitool -H $IPMI_IP -U $IPMI_USERNAME -P $IPMI_PASSWORD power on || { echo 'Failed powering on' ; return 1; }

  echo -e "\nChecking if host ${GOVC_URL} is online!\n"
  # Check to see when host comes online and timeout after 5 minutes
  local attempt_counter=0
  local max_attempts=60
  until $(curl -k --output /dev/null --silent --head --fail https://${GOVC_URL}); do
    if [ ${attempt_counter} -eq ${max_attempts} ];then
      echo "Max attempts reached"
      return 1
    fi
    attempt_counter=$(expr ${attempt_counter} + 1)
    local current_try=$(expr ${max_attempts} - ${attempt_counter})
    echo "Host ${GOVC_URL} not online yet, ${current_try} more retries left"
    sleep 2
  done

  sleep 5

  echo -e "\nHost ${GOVC_URL} online!\n"

  local host="$(govc ls /ha-datacenter/host)"

  govc host.maintenance.exit ${host} || { echo 'Failed exiting maintenance' ; return 1; }

  # Suspect vCenter first to ensure vCLS doesn't get re-created
  govc vm.power -on -wait "/ha-datacenter/vm/vcsa8"
  # Suspect untangle router
  govc vm.power -on -wait "/ha-datacenter/vm/untangle"

  echo -e "\n Power on compelete"
  )
}

function suspend_vm() {
  local vm_path=$1
  [ -z "${vm_path:-}" ] && echo 'A VM name must be passed as a parameter' && return 1

  # TODO handle VM not existing!
  if [[ "$(govc vm.info ${vm_path})" == *"poweredOn"* ]]; then
    echo -e "Suspending the VM ${vm_path}\n"
    govc vm.power -suspend -wait "${vm_path}"
  else
    echo -e "VM ${vm_path} is not powered on\n"
  fi
}

function laboff() {
  ( 
  # Ensure correct vars are set and error if not
  [ -z "${ESXI_IP:-}" ] && echo '$ESXI_IP must be set' && return 1
  [ -z "${ESXI_USERNAME:-}" ] && echo '$ESXI_USERNAME must be set' && return 1
  [ -z "${ESXI_PASSWORD:-}" ] && echo '$ESXI_PASSWORD must be set' && return 1
  export GOVC_URL=$ESXI_IP
  export GOVC_USERNAME=$ESXI_USERNAME
  export GOVC_PASSWORD=$ESXI_PASSWORD
  export GOVC_INSECURE=true
  unset GOVC_DATACENTER GOVC_HOST GOVC_DATASTORE GOVC_LIBRARY
  
  if $(curl -k --output /dev/null --silent --head --fail -m 1 https://${GOVC_URL}); then
    echo -e "Host ${GOVC_URL} is online. Shutting down\n"
  else
    echo "Host is already offline"
    return 0
  fi

  # Suspend vCenter first to ensure vCLS doesn't get re-created
  suspend_vm "/ha-datacenter/vm/vcsa8"
  # Suspend untangle router
  suspend_vm "/ha-datacenter/vm/untangle"

  local VMS=$(govc ls /ha-datacenter/vm)

  # Power off vCLS VMs
  local VCLS_VMS=$(echo "$VMS" |grep "vCLS")
  for VM in "${VCLS_VMS}"; do
    local VCLS_VM_STATE="$(govc vm.info ${VM})"
    local VM_NAME=$(echo "${VCLS_VM_STATE}" |grep -i "Name:           " |sed s'/Name:           //')
    if [[ "${VCLS_VM_STATE}" == *"poweredOn"* ]]; then
      echo -e "Terminating vCLS VM ${VM_NAME}"
      govc vm.power -off -wait $(echo "${VCLS_VM_STATE}" |grep -i "Path:         " |sed s'/  Path:         //')
    else
      echo -e "vCLS VM ${VM_NAME} already powered off"
    fi
  done

  # Shuddown VMs
  local VMS_TO_POWER_OFF=""
  for VM in $VMS; do
    local VM_STATE=$(govc vm.info "${VM}")
    if [[ "${VM_STATE}" == *"poweredOn"* ]]; then
      VMS_TO_POWER_OFF="${VMS_TO_POWER_OFF} $(echo "${VM_STATE}" |grep -i "Path:         " | sed s'/  Path:         //')"
    fi
  done
  if [ ! -z "${VMS_TO_POWER_OFF}" ]; then
    local VMS_TO_POWER_OFF_NAMES=$(echo "${VMS_TO_POWER_OFF}" | sed  s'/\/ha-datacenter\/vm\///'g)
    echo -e "\nSuspending VMs:\n ${VMS_TO_POWER_OFF_NAMES}\n"
    govc vm.power -s -wait $VMS_TO_POWER_OFF
  else
    echo -e "\nNo VMs to shutdown"
  fi

  # Shutdown hosts
  local HOST="$(govc ls /ha-datacenter/host)"
  if ! govc host.info $HOST |grep -i "Maintenance Mode"; then
    govc host.maintenance.enter  $HOST
  else
    echo "Host ${HOST} is already in maintenance mode"
  fi
  govc host.shutdown "${HOST}"
  )
}

function tkgcli () {
  version=${1:-*}
  os="$(uname -s | awk '{print tolower($0)}')" 
  if ! command -v vcc &> /dev/null; then umask 002
    curl -OLf "https://github.com/vmware-labs/vmware-customer-connect-cli/releases/download/v1.1.3/vcc-${os}-v1.1.3"
    mv vmd-${os}-v0.3.0 "$HOME/.local/bin/vcc"
    chmod +x "$HOME/.local/bin/vcc"
  fi
  echo "Attempting to download version $version"
  vcc download -p vmware_tanzu_kubernetes_grid -s tkg -v "$version" -f "tanzu-cli-bundle-${os}-amd64.*" --accepteula
  tanzu_dir="${TANZU_DIR:-$HOME/tanzu}" 
  echo "Extracting to $tanzu_dir"
  mkdir -p "$tanzu_dir"
  find $tanzu_dir -mindepth 1 -maxdepth 1 | xargs -rn1 rm -rf
  tar -xvf "$HOME/vcc-downloads/tanzu-cli-bundle-${os}-amd64.tar.gz" --directory "$tanzu_dir"
  cli="$(find $tanzu_dir -name tanzu-core-${os}_amd64)" || (return 1)
  echo "Moving $cli to $HOME/.local/bin/tanzu"
  mv "$cli" "$HOME/.local/bin/tanzu"
  tanzu plugin clean
  tanzu init
}

function tason() {
  (
    set -xeuo pipefail
  # Ensure correct vars are set and error if not
  [ -z "${ESXI_IP:-}" ] && echo '$ESXI_IP must be set' && return 1
  [ -z "${ESXI_USERNAME:-}" ] && echo '$ESXI_USERNAME must be set' && return 1
  [ -z "${ESXI_PASSWORD:-}" ] && echo '$ESXI_PASSWORD must be set' && return 1
  [ -z "${OM_USERNAME:-}" ] && echo '$OM_USERNAME must be set' && return 1
  [ -z "${OM_PASSWORD:-}" ] && echo '$OM_PASSWORD must be set' && return 1
  [ -z "${OM_TARGET:-}" ] && echo '$OM_TARGET must be set' && return 1
  unset GOVC_DATACENTER GOVC_HOST GOVC_DATASTORE GOVC_LIBRARY
  export GOVC_URL=$ESXI_IP
  export GOVC_USERNAME=$ESXI_USERNAME
  export GOVC_PASSWORD=$ESXI_PASSWORD
  export GOVC_INSECURE=true
  export OM_SKIP_SSL_VALIDATION=true

  # Power up opsman
  # govc vm.power -on "/ha-datacenter/vm/tas-direct-ops-manager"

  # Power on Bosh managed VMs
  govc vm.power -on -wait -force /ha-datacenter/vm/tas-direct-ops-manager
  local VMS="$(govc ls '/ha-datacenter/vm/vm-*')"

   while IFS= read -r VM; do
    local VM_STATE=$(govc vm.info "${VM}")
    local VM_PATH="$(echo "$VM_STATE" |grep -i "Path:         " | sed s'/  Path:         //')"
    if [[ "${VM_STATE}" != *"poweredOn"* ]]; then
      govc vm.power -on -wait -force "$VM_PATH"
    else
      echo "VM $VM_PATH already powered on"
    fi

  done <<<"$VMS"

  echo -e "\nUnlocking opsman"
  curl -k -X PUT -H "Content-Type: application/json" --retry-all-errors --retry 20 \
    -d "{\"passphrase\": \"${OM_PASSWORD}${OM_PASSWORD}\"}" https://${OM_TARGET}/api/v0/unlock
 
  eval "`om bosh-env`"
  local CF_DEP=$(bosh deps |grep ^cf- | cut -d ' ' -f 1)
  #TODO wait until all VMs are ready

  echo -e "\nTAS on compelete - check Bosh for state"
  set +x
  )
}

function tasoff() {
  (
  # Ensure correct vars are set and error if not
  [ -z "${ESXI_IP:-}" ] && echo '$ESXI_IP must be set' && return 1
  [ -z "${ESXI_USERNAME:-}" ] && echo '$ESXI_USERNAME must be set' && return 1
  [ -z "${ESXI_PASSWORD:-}" ] && echo '$ESXI_PASSWORD must be set' && return 1
  unset GOVC_DATACENTER GOVC_HOST GOVC_DATASTORE GOVC_LIBRARY
  export GOVC_URL=$ESXI_IP
  export GOVC_USERNAME=$ESXI_USERNAME
  export GOVC_PASSWORD=$ESXI_PASSWORD
  export GOVC_INSECURE=true

  # Power off opsman
  govc vm.power -off "/ha-datacenter/vm/tas-direct-ops-manager"

  # Power on Bosh managed VMs
  local VMS="$(govc ls /ha-datacenter/vm/vm-*)"
  govc vm.power -off -wait $VMS

  echo -e "\nTAS off compelete"
  )
}

function kga {
  for i in $(kubectl api-resources --verbs=list --namespaced -o name | grep -v "events.events.k8s.io" | grep -v "events" | sort | uniq); do
    kubectl get -n ${1} --show-kind --ignore-not-found ${i}
  done
}
