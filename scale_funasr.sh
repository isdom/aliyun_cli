#!/bin/bash
if [ "$#" -lt 1 ]; then
  echo "usage: ./funasr_actconn.sh <ScalingGroupId> [inc_rule] [dec_rule]"
  exit -1
fi

max_conn_per_inst=25
min_conn_per_inst=10
inst_cnt=0
total_conn_cnt=0

insts_json=$(aliyun ess DescribeScalingInstances \
           --ScalingGroupId $1 \
           --HealthStatus Healthy --PageSize 100 --version 2022-02-22 --method POST --force)
insts_num=$(echo ${insts_json}| jq '.ScalingInstances|length')
for idx in `seq 0 $((${insts_num}-1))`
do
    inst_id=$(echo ${insts_json} | jq .ScalingInstances[${idx}].InstanceId | sed 's/\"//g')
    inst_cnt=$((${inst_cnt} + 1))
    echo "run cmd: ${inst_cnt}/${inst_id}"
    invoke_id=$(aliyun ecs RunCommand \
           --CommandContent 'IyEvYmluL2Jhc2gKZWNobyAkKG5ldHN0YXQgLWFucHxncmVwIDEwMDk1fGdyZXAgRVNUQUJMSVNIRUR8d2MgLWwp' \
           --ContentEncoding 'Base64' --Username 'root' --Timeout '60' --Type 'RunShellScript' \
           --InstanceId.1 ${inst_id}\
           | jq .InvokeId | sed 's/\"//g')
    sleep 2
    cnt_output=$(aliyun ecs DescribeInvocationResults --InvokeId ${invoke_id} \
                | jq .Invocation.InvocationResults.InvocationResult[0].Output | sed 's/\"//g')
    conn_cnt=$(printf "%s" ${cnt_output}| base64 -d)
    echo "${inst_id}: act conn num: ${conn_cnt}"
    total_conn_cnt=$((${total_conn_cnt} + ${conn_cnt}))
done

echo "$1 's total instance num: ${inst_cnt} / total act conn num: ${total_conn_cnt}"

if  [ ! "$2" ] ;then
    echo "!NO! inc rule. skip scaling action"
    exit 0
else
    echo "using inc rule: $2"
fi

if [ ${total_conn_cnt} -gt $((${inst_cnt} * ${max_conn_per_inst})) ]
then 
    echo "too many total conn, increase instance by rule..."
    aliyun ess ExecuteScalingRule --ScalingRuleAri $2 --version 2022-02-22 --method POST --force
fi

if  [ ! "$3" ] ;then
    echo "!NO! dec rule, skip scaling action"
    exit 0
else
    echo "using dec rule: $3"
fi

if [ ${total_conn_cnt} -lt $((${inst_cnt} * ${min_conn_per_inst})) ]
then 
    echo "too less total conn, decrease instance by rule..."
    aliyun ess ExecuteScalingRule --ScalingRuleAri $3 --version 2022-02-22 --method POST --force
fi
