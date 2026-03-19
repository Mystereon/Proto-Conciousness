# Indigo - Tilt Development Environment
# Usage: kind create cluster --name indigo && tilt up

docker_build(
    'indigo',
    '.',
    live_update=[
        sync('./app', '/app'),
        run('pip install -r /app/requirements.txt', trigger=['./app/requirements.txt']),
    ],
)

k8s_yaml([
    'k8s/configmap.yaml',
    'k8s/pvc.yaml',
    'k8s/deployment.yaml',
    'k8s/service.yaml',
])

k8s_resource('indigo', port_forwards='5000:5000')
