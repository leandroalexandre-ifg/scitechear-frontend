# Diagramas espelhados desatualizados — o que corrigimos e o que vocês precisam espelhar

**Data:** 07/09/2026
**De:** SciTech-frontend
**Para:** backend SciTech Ear
**Assunto:** `docs/diagrams/01`, `03`, `04` e o `ARCHITECTURE.md` §6 passo 3

Fomos conferir se os diagramas SVG tinham acompanhado as últimas rodadas.
Quatro dos cinco não tinham. Três deles — e um trecho do `ARCHITECTURE.md` —
são **espelhados nos dois repositórios**, então a correção precisa chegar aí
também, senão as cópias divergem.

Já aplicamos tudo do nosso lado. Os arquivos corrigidos estão em
`docs/diagrams/` neste repositório e podem ser copiados como estão.

---

## 1. O erro que mais importa: o worker não é uma thread

`01-system-context.svg` mostrava uma caixa **"Job Executor — execução em
background thread"**, e `04-pipeline-sequence.svg` tinha o passo
**"4. executar(job_id) em background thread"**. O `ARCHITECTURE.md`, §6 passo
3, dizia a mesma coisa em prosa:

> Um executor de jobs (`job_executor.py`) dispara o processamento em uma
> thread separada, para não bloquear a resposta HTTP.

Hoje é um **worker dedicado, em processo separado** (`python -m app.worker`),
e a diferença é operacional, não cosmética: **sem o worker no ar, todo job
fica em `queued` para sempre**, e a API não dá nenhum sinal disso. Foi
exatamente o que faltava no nosso README e vocês apontaram na primeira rodada.

Um diagrama que mostra o processamento como thread da API leva quem for
operar o sistema a achar que subir a API basta.

**Corrigido para:** "Worker dedicado — processo separado da API — sem ele, o
job fica em queued para sempre".

## 2. `01-system-context.svg` não tinha autenticação nenhuma

O diagrama de contexto mostrava três canais entre app e backend — voz, upload
e status/resultado — e **nenhuma menção a `/auth`**. Lido literalmente, ele
descrevia um sistema sem autenticação, que é o que o app de fato era antes
de 03/09.

**Corrigido:** o canal da esquerda passou a incluir `/auth/*` (JWT + refresh)
e `GET /participants`, o da direita ganhou `GET /meetings`, a caixa da API
lista as rotas reais, e há um rodapé em negrito:

> Toda rota exige `Authorization: Bearer`, exceto `/auth/register`,
> `/auth/login`, `/auth/refresh` e `/health`.
> Jobs, resultados e perfis de voz são escopados por `user_id` no servidor:
> `/status` e `/resultado` devolvem 404 tanto para job inexistente quanto
> para job de outro dono.

Também trocamos "VoiceRepository — embeddings por `participant_id`" por
"…, escopados por `user_id`", que é o que vocês confirmaram na rodada 3.

## 3. `03-job-state-machine.svg` afirmava algo falso sobre o cliente

O rodapé dizia:

> O cliente exibe `error.message` e oferece "tentar novamente" / "voltar".

**Não exibe mais.** Desde a rodada 2, o app traduz o `error.code` para
português e o `error.message` não chega à tela em caminho nenhum — nem como
fallback, justamente porque é o `str(exc)` da exceção Python, às vezes com
caminho de arquivo do servidor dentro. Há teste garantindo que um `message`
com `Traceback` ou `/srv/...` não escapa.

Este é o tipo de erro que se propaga: alguém lê o diagrama, presume que o
cliente mostra o `message`, e passa a escrever mensagens de exceção como se
fossem texto de usuário final.

**Corrigido**, e aproveitamos para acrescentar ao diagrama o comportamento de
estágios curtos, que também é do contrato e não estava desenhado:

> O cliente recebe o estado ATUAL a cada 1s pelo WebSocket, não a sequência
> de transições: estágios curtos podem não aparecer nenhuma vez. No E2E real,
> `identifying` levou 0,07s e `summarizing` 0,00s — nenhum dos dois apareceu.
> Pular estado é normal, não é anomalia.

## 4. `04-pipeline-sequence.svg` não tinha token em lugar nenhum

O passo 1 era `POST /upload (áudio WAV + participants JSON)`, sem
`Authorization`. Corrigido para incluir o `Bearer`, e acrescentamos uma linha
sobre a renovação proativa, que é a razão de o upload não tomar 401 no meio:

> Antes do passo 1, o `ApiClient` renova o access token se faltarem menos de
> 2 min: um upload multipart que tomasse 401 teria o corpo já consumido.

O loop do WebSocket também foi atualizado para o push a cada 1s com polling
de 3s como plano B, em vez da descrição antiga de "WebSocket com fallback".

## 5. `06-data-contract.svg` está correto

Conferimos campo a campo contra `lib/models/meeting_result.dart`: o
`MeetingResult` não mudou e as duas invariantes continuam valendo. Nada a
fazer.

---

## O que pedimos

1. **Copiar os quatro arquivos** de `docs/diagrams/` deste repositório
   (`01`, `03`, `04` e o `07` novo, se quiserem) para a cópia de vocês.
2. **Aplicar a correção do §6 passo 3 do `ARCHITECTURE.md`** — a nossa versão
   está no repositório e descreve o worker como processo separado.
3. **Conferir se o `job_executor.py` ainda existe** do lado de vocês, ou se
   virou outra coisa quando o worker dedicado entrou. Escrevemos "isso
   substituiu o modelo anterior" a partir do que sabemos de fora; se o nome
   do arquivo ou o desenho interno for outro, corrijam a frase — é a parte
   deste documento sobre a qual temos menos visibilidade.

Nenhum dos quatro é urgente: são figuras, não comportamento. Mas o do worker
como thread é o que mais engana na hora de operar, e o do `error.message` é o
que mais engana na hora de escrever código novo.

---

## Uma observação de método

Os diagramas ficaram para trás porque **nada os obriga a acompanhar o
código**. Os documentos em prosa foram corrigidos várias vezes nestas
rodadas; as figuras, nenhuma — e uma figura errada é mais convincente que um
parágrafo errado, porque parece um resumo autorizado.

Não temos uma solução boa para isso. O que fizemos foi mínimo: extrair o
texto de cada SVG e conferir afirmação por afirmação contra o código, o que
leva uns minutos e dá para repetir a cada rodada em que o contrato mudar.
