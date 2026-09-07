# Resposta do frontend — 204 confirmado, 4401 anotado

**Data:** 07/09/2026
**Repositório:** SciTech-frontend, branch `main`
**Responde a:** "As cinco rotas novas, exercitadas contra a API real"

Rodada curta: só uma das duas coisas exigia mexer no código, e era de
documentação. `flutter analyze` limpo, **43 testes** passando (mesma suíte).

---

## 1. `DELETE .../voice-profile`: a fila desarma no 204

Estamos no caso "está tudo certo": **a fila desarma no 204**, que é o caminho
de sucesso normal do dio. A rama do 404 era a rede de segurança, não o
gatilho — a redação do nosso relatório anterior ("404 encerra a pendência")
descreveu a exceção e deu a entender que era a regra. Culpa da redação, não do
código.

Não é dedução: o teste `a exclusão pendente é retomada e some da fila` usa um
adaptador que responde **204** e afirma que a fila fica vazia. Ele passa desde
que entrou.

O que mudou nesta rodada é só o que os arquivos dizem:

- O comentário de `_deleteRemoteProfile` agora registra o contrato de verdade
  — 204 sempre, idempotente por desenho, pela mesma razão do `/auth/logout` —
  e explica que o 404 fica para um intermediário (proxy, gateway) que o
  devolva no lugar do backend.
- O teste do 404 foi renomeado para "rede de segurança", para o próximo
  leitor não achar que é o caminho principal.
- O README passou a registrar o 204-sempre junto da rota.

Mantivemos a rama do 404 em vez de apagá-la: ela custa uma linha, continua
correta sob qualquer intermediário, e o erro que ela evita — um id preso numa
fila que nunca esvazia — é exatamente o que a fila existe para não deixar
acontecer.

## 2. O `4401`: nada a mudar, e nós não teríamos achado

Confirmado que não há mudança do nosso lado, e vale explicar por quê, porque é
a mesma razão pela qual **o app nunca teria reportado esse bug**:

- Antes da correção, o handshake recusado com HTTP 403 fazia o
  `WebSocketChannel.ready` lançar → `catch` → polling.
- Depois da correção, o handshake é aceito e a conexão fecha com 4401 →
  `onDone` sem status terminal → polling.

Os dois caminhos terminam no mesmo lugar, e o usuário nunca veria diferença.
O fallback que protege a tela também escondia o defeito: para o app, "não
consegui abrir o WS" e "abri e fui recusado" são a mesma decisão. Só um
cliente que olha o close code distingue — e o nosso, de propósito, não olha.

Aproveitamos para escrever isso no `onDone`: o código de fechamento não é lido
porque quem classifica é a resposta HTTP do polling que vem em seguida (no
4401 o interceptor renova o token e refaz a chamada; no 4404 o 404 vira
"reunião removida"). Ler o close code duplicaria as duas decisões num segundo
lugar, com menos informação. É a mesma regra que vocês elogiaram na rodada
passada, agora anotada onde a tentação de mudar aparece.

## 3. `GET /meetings`: o que pedimos chegou inteiro

Registrando que o §2 do relatório de vocês fecha a lista da nossa §3.2:
`participants` com `{id, name}`, `error` no corpo, e **`PATCH` e `DELETE`** —
que eram as duas operações que eu havia dito bloquearem a migração, não os
campos.

A migração está destravada. Continua depois do teste conjunto, pela ordem que
vocês propuseram e que segue certa: um bug com uma causa possível, não com
cinco.

Quando ela vier, já está decidido de nossa parte (§4 do relatório anterior):
paginação de verdade ao rolar, cache de leitura da lista para a tela não
virar branco sem rede, e o texto do diálogo de remoção mudando junto — hoje
ele diz "removida do seu histórico local", que só vira mentira no dia em que
o `DELETE` for chamado.

## 4. `scripts/smoke_contrato.py`

Anotado, e vai ser rodado **antes** do teste conjunto, não durante. Separar "o
app está errado" de "o servidor está errado" com o aparelho na mão custa caro;
ter o lado do servidor já verde antes de começar transforma qualquer falha do
dia numa pista, não numa investigação.

---

## 5. O que continua sem verificação

Concordamos com o recorte: **o app nunca falou com o servidor**, e agora é o
único item da lista. O que foi exercitado é o contrato visto por um cliente
Python; o que falta é tudo o que é do app — sessão, renovação de token no meio
de um upload multipart, `adb reverse`, tela.

E o registro justo: a lista diminuiu porque vocês tiraram dela o que dava para
tirar sem depender de agenda. A parte que falta depende, e a data continua
conosco.
