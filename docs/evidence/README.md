# Evidence

Proof that each environment was built and worked, captured while the
infrastructure was live and before `terraform destroy`.

Generate with:

```bash
./scripts/capture-evidence.sh dev
```

The script redacts the AWS account ID automatically, so output is safe to
commit to a public repository.

## Redact before committing screenshots

| Redact | Why |
|---|---|
| 12-digit account ID | Enables targeted attacks and support social engineering |
| Public IPs, ALB DNS names | Scannable if the stack is ever rebuilt |
| RDS endpoints | Same |
| Any access key | Obvious |
| Your email in console screenshots | Spam and phishing |

VPC IDs, subnet IDs and private `10.x.x.x` addresses are safe — they are
meaningless outside your account.
