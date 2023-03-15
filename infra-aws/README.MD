


## 


## Stock Tracer

```shell
terraform init
```

```shell
terraform plan
```

```shell
terraform apply -auto-approve
```

```shell
terraform destroy -auto-approve
```

```shell
bash << EOF
echo Configurando o kubectl
rm token
eval "scp -i id_rsa ubuntu@$(terraform output -raw scoobychat_server_spot_ip):/tmp/token token"
eval "sed -i -e 's/token: .*/token: $(cat token)/g' ~/.kube/config"
EOF
```

```shell
bash << EOF
echo Aguardando o host ficar disponível
sudo systemd-resolve --flush-caches
systemd-resolve --flush-caches
while true; do if ping -c 1 scoobychat.renatomoura.top &> /dev/null; then break; else sudo systemd-resolve --flush-caches; sleep 2; echo Tentando conectar no host; fi done

echo Host disponível...
EOF
```

```shell
bash << EOF
#ping scoobychat.renatomoura.top
sudo systemd-resolve --flush-caches
kubectl get pods -n default
kubectl apply -f ../k8s/
EOF
```

1 -
```shell
cd ..
docker build -t scoobychat.renatomoura.top:32000/scoobychat:1 .
docker tag scoobychat.renatomoura.top:32000/scoobychat:1 scoobychat.renatomoura.top:32000/scoobychat:latest
docker push scoobychat.renatomoura.top:32000/scoobychat:latest
kubectl rollout restart deployment/scoobychat -n default
```

3:
```shell
cd ..
kubectl rollout restart deployment/scoobychat -n default
#kubectl apply -f ./k8s
```


https://timberwolf-mastiff-9776.twil.io/demo-reply
