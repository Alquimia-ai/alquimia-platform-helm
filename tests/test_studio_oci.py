"""Render the real chart; no cluster or credentials are required.

Run: uv run --no-project --with PyYAML python -m unittest discover -s tests -v
"""
from pathlib import Path
import copy
import subprocess
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
OVERLAY = ROOT / 'chart/values-eks-alquimia-code-studio.yaml'


def render(*arguments):
    result = subprocess.run(
        ['helm', 'template', 'alquimia', str(ROOT / 'chart'),
         '--namespace', 'alquimia-platform', *arguments],
        capture_output=True, text=True, check=True,
    )
    return {(doc['kind'], doc['metadata']['name']): doc
            for doc in yaml.safe_load_all(result.stdout) if doc}


def environment(documents):
    deployment = documents[('Deployment', 'alquimia-studio')]
    return {entry['name']: entry for entry in deployment['spec']['template']['spec']['containers'][0]['env']}


class StudioOciTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.default = render()
        cls.eks = render('-f', str(OVERLAY))

    def test_defaults_preserve_existing_environment(self):
        self.assertEqual(set(environment(self.default)), {'NEDB_DATA_DIR'})

    def test_eks_uses_exact_registry_and_existing_secret(self):
        env = environment(self.eks)
        self.assertEqual(env['OCI_ALLOWED_REGISTRIES']['value'], 'registry.alquimia.ai')
        self.assertEqual(env['OCI_REGISTRY_CREDENTIALS'], {
            'name': 'OCI_REGISTRY_CREDENTIALS',
            'valueFrom': {'secretKeyRef': {
                'name': 'alquimia-studio-external-oci', 'key': 'OCI_REGISTRY_CREDENTIALS',
            }},
        })
        self.assertNotIn(('Secret', 'alquimia-studio-external-oci'), self.eks)

    def test_overlay_only_contains_studio_oci_metadata(self):
        overlay = yaml.safe_load(OVERLAY.read_text())
        self.assertEqual(set(overlay), {'studio'})
        self.assertEqual(set(overlay['studio']), {'oci'})
        self.assertEqual(set(overlay['studio']['oci']), {'allowedRegistries', 'credentialsSecret'})

    def test_non_studio_resources_do_not_change(self):
        self.assertEqual(set(self.default), set(self.eks))
        for key, document in self.default.items():
            # Existing templates generate random TLS/Qdrant Secret bytes per render.
            if key[0] == 'Secret' or key[1].startswith('alquimia-studio'):
                continue
            expected = copy.deepcopy(document)
            actual = copy.deepcopy(self.eks[key])
            if key == ('StatefulSet', 'oras-registry'):
                # The existing CA is reused in-cluster, but offline renders generate it.
                expected['spec']['template']['metadata']['annotations'].pop('checksum/registry-ca')
                actual['spec']['template']['metadata']['annotations'].pop('checksum/registry-ca')
            with self.subTest(resource=key):
                self.assertEqual(expected, actual)

    def test_zero_trust_runtime_is_unchanged(self):
        settings = ['--set', 'runtime.zeroTrust.enabled=true']
        baseline = render(*settings)
        eks = render(*settings, '-f', str(OVERLAY))
        for key in [('Deployment', 'alquimia-runtime-master'), ('Deployment', 'alquimia-runtime-worker'),
                    ('ConfigMap', 'alquimia-config')]:
            with self.subTest(resource=key):
                self.assertTrue(key in baseline, f'Missing resource: {key}')
                self.assertEqual(baseline[key], eks[key])

    def test_allowed_hosts_can_be_used_without_credentials(self):
        env = environment(render('--set', 'studio.oci.allowedRegistries[0]=registry.example.test',
                                 '--set', 'studio.oci.allowedRegistries[1]=second.example.test'))
        self.assertEqual(env['OCI_ALLOWED_REGISTRIES']['value'],
                         'registry.example.test,second.example.test')
        self.assertNotIn('OCI_REGISTRY_CREDENTIALS', env)

    def test_disabling_studio_does_not_create_its_resources(self):
        documents = render('-f', str(OVERLAY), '--set', 'studio.enabled=false')
        self.assertFalse(any(name.startswith('alquimia-studio') for _, name in documents))


if __name__ == '__main__':
    unittest.main()
