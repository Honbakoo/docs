# 🔌 Honbakoo Connector & Ingestion Pipeline Specification

> **Módulo:** Ingestão de Conteúdo & Scrapers  
> **Objetivo:** Isolar 100% da instabilidade de fontes externas, garantindo que o catálogo do Honbakoo receba dados limpos, sanitizados e deduplicados sem risco de indisponibilidade ou corrupção de banco.

---

## 1. Princípios de Ingestão Desacoplada

1. **Zero-Trust Input:** Nenhum dado vindo de scraper externo é gravado diretamente nas tabelas de produção sem passar pelo estágio de **Quarentena e Validação Estrutural**.
2. **Sandbox de Execução:** Conectores leves rodam isolados em WebAssembly (Wasm) ou runtime JavaScript (`goja`) dentro de workers sem acesso direto ao banco relacional. Scrapers pesados (Selenium/Python) rodam externamente e utilizam a rota de ingestão autenticada (`POST /api/v1/ingest/*`) via API Key (`hbk_...`).
3. **Resiliência a Mudanças de Layout:** Se o site de origem alterar seu HTML/CSS, o worker falha de forma graciosa para uma **Fila de Cartas Mortas (Dead Letter Queue - DLQ)** sem afetar a disponibilidade da API pública.
4. **Content-Addressed Pipeline:** O download de imagens calcula o hash SHA-256 no momento do streaming; se a imagem já existir no banco (capa, página de crédito), o download do binário é abortado antes de salvar no disco/S3.

---

## 2. Fluxo do Pipeline de Ingestão

```mermaid
flowchart TD
    ExternalSource[(Sites Externos / Scrapers)] --> IngestQueue[Fila de Tarefas: Redis / Asynq]
    
    subgraph "Worker de Ingestão (Sandboxed)"
        IngestQueue --> FetchJob[Fetcher: TLS Fingerprint Spoofing]
        FetchJob --> Parser[Parser do Conector: Extração de Metadados]
        Parser --> Sanitizer[Sanitização: XSS, Tag Mapping, Normalização]
    end

    Sanitizer --> QualityGate{Validação de Qualidade}
    
    QualityGate -->|Falha estrutural| DLQ[Dead Letter Queue / Quarentena]
    QualityGate -->|Aprovado| MediaDownloader[Media Ingestion Worker]
    
    subgraph "Processamento de Mídia"
        MediaDownloader --> HashCalc[Cálculo SHA-256 on-the-fly]
        HashCalc --> CheckBlacklist{Hash em Blacklist DMCA?}
        CheckBlacklist -->|Sim| AbortDrop[Descarta & Alerta Moderação]
        CheckBlacklist -->|Não| DeduplicateCheck{Arquivo já existe?}
        DeduplicateCheck -->|Sim| LinkExisting[Apenas referencia media_id]
        DeduplicateCheck -->|Não| Optimizer[libvips: Valida Magic Bytes & WebP]
        Optimizer --> StorageSave[(Storage: Local / Cloudflare R2)]
    end

    StorageSave --> DBCommit[(PostgreSQL: Catálogo Atualizado)]
    LinkExisting --> DBCommit
```

---

## 3. O Contrato Padronizado de Conectores (`Connector Interface`)

Cada scraper implementa uma interface canônica e declarativa:

```typescript
// Interface Universal do Conector
interface HonbakooConnector {
  readonly id: string;           // ex: 'nhentai-v1', 'mangadex-v5'
  readonly name: string;         // Nome legível da fonte
  readonly baseUrl: string;      // URL base
  readonly rateLimitRPS: number; // Limite de requisições por segundo para não tomar ban

  // Métodos obrigatórios
  search(query: string, filters: SearchFilters, page: number): Promise<SearchResponse>;
  getDetails(remoteId: string): Promise<RemoteMangaDetails>;
  getChapters(remoteId: string): Promise<RemoteChapter[]>;
  getPageUrls(remoteChapterId: string): Promise<string[]>;
}
```

### 3.1 Tratamento de Evasão de Bloqueios (Anti-Bot & WAF)
* **TLS Client Hello Spoofing:** Conectores HTTP utilizam `curl-impersonate` para imitar os cabeçalhos de handshake TLS de um navegador Chrome desktop real.
* **Pool de Proxies Rotativos:** Configurado por variável de ambiente (`INGEST_PROXY_POOL=http://user:pass@proxy1,http://...`), permitindo alternar IPs de saída caso a fonte imponha rate limit geográfico.

### 3.2 Defesa Estrita contra SSRF e DNS Rebinding (OWASP Compliance)
Conectores buscam URLs externas de terceiros; permitir requisições cegas sem restrição de rede expõe a infraestrutura interna (metadados AWS/Cloud, portas locais do Postgres e Redis). O pipeline implementa defesa em camadas:

1. **Validação do Endereço IP Conectado (Anti-DNS Rebinding):**
   * A resolução DNS é desacoplada da conexão.
   * O cliente HTTP em Go utiliza um `net.Dialer.Control` personalizado: após a resolução DNS do domínio de destino, o IP IPV4/IPV6 efetivo é inspecionado antes do handshake TCP.
   * **Bloqueio Incondicional de Ranges Privados e Reservados:**
     * `127.0.0.0/8` (Loopback / Localhost)
     * `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` (RFC 1918 Private LAN)
     * `169.254.0.0/16` (Link-Local e Cloud Instance Metadata: `169.254.169.254`)
     * `::1/128`, `fc00::/7`, `fe80::/10` (IPv6 Local e Link-Local)
     * Se o IP resolvido pertencer a qualquer uma dessas faixas, **a conexão é abortada antes do primeiro byte de tráfego**.
2. **Restrição Rígida de Redirecionamentos HTTP:**
   * O cliente HTTP não segue redirecionamentos cegamente (`CheckRedirect` hook).
   * Cada salto (`301/302/307`) passa pela mesma validação de DNS e checagem de IP proibido. Limite máximo de **3 redirecionamentos**.
3. **Limitação de Duração e Tamanho de Download:**
   * Timeout de conexão: 5 segundos.
   * Timeout total de download por mídia: 15 segundos.
   * Streaming delimitado por `io.LimitReader`: downloads que ultrapassarem 15MB são cortados imediatamente para evitar Denial of Service por streams infinitos.

---

## 4. Política de Retentativas e Dead Letter Queue (DLQ)

* **Retentativa com Backoff Exponencial com Jitter:**
  * Tentativa 1: Imediata.
  * Tentativa 2: Após 30 segundos.
  * Tentativa 3: Após 5 minutos.
  * Tentativa 4: Após 30 minutos.
* **Envio para DLQ:** Se um capítulo falhar após 4 tentativas consecutivas (ex: página 404 na fonte original ou timeout), o job é arquivado na fila de mortas com o payload original e a stack trace do erro.
* **Alerta:** A métrica `queue_failures_total{queue="ingest_dlq"}` dispara um aviso no dashboard de observabilidade.
