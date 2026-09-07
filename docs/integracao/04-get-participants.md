# Resposta do frontend — `GET /participants` consumido

**Data:** 07/09/2026
**Repositório:** SciTech-frontend, branch `main`
**Responde a:** "`GET /participants`: reinstalar deixa de órfar o cadastro"

Consumido. O `display_name` já estar no `profile.json` muda mesmo o desenho —
a listagem devolvendo id **e** nome é a diferença entre limpar sujeira depois
e não sujar. Implementamos os três pontos do §2, com uma ordem de operações
que vale explicar porque não era óbvia.

`flutter analyze` limpo; suíte em **43 testes** (eram 34), todos passando.

---

## 1. O que o app faz agora

### Semeia o cadastro em instalação nova

`ParticipantService.seedFromServerIfEmpty()`, chamado pela tela inicial (a
primeira depois do login) em segundo plano, sem bloquear nada. Se o cadastro
local está vazio, ele vem de `GET /participants`: o usuário reencontra as
pessoas que já cadastrou, com a voz pronta e **nada para regravar**.

Se a chamada falhar, não tem drama nem retentativa agendada — a tela de
participantes refaz a mesma sincronização toda vez que abre.

### A listagem substituiu o `GET .../voice-profile` um a um

Como vocês previram, com vantagem: uma chamada em vez de N, e ela também
revela perfis que existem no servidor e sumiram do app — que era o caso
impossível de detectar antes. O `voice-profile` por id não é mais chamado em
lugar nenhum do app; removemos o código que o usava, e a rota continua
existindo para quem precisar.

Um perfil que **some** da listagem volta a "não sincronizado", mas o
participante **não é apagado** do cadastro local. Ele é do usuário: some
quando ele mandar, não quando o servidor deixar de listar. Perder o cadastro
local também apagaria o nome, que é o que torna a lista legível.

### Falha de rede não é ausência

Mantida, e agora com uma consequência maior: uma listagem que não respondeu
não pode virar "esta conta não tem participante nenhum", porque agora existe
código que semeia e reconcilia a partir dessa resposta. `null` é "não sei" e
devolve o cadastro local intacto — coberto por teste.

---

## 2. A ordem que não era óbvia: exclusão pendente antes da listagem

A fila de exclusões pendentes da rodada anterior e a listagem desta se cruzam
num caso que quebra as duas se a ordem estiver errada:

1. O usuário apaga um participante **sem rede**. O registro local some; o id
   fica na fila, porque o `DELETE` falhou.
2. Ele abre a tela de participantes com conexão.
3. Se a listagem rodasse primeiro, o servidor ainda teria aquele perfil — e o
   app traria de volta, como cadastro, **exatamente quem o usuário mandou
   apagar**.

Então `syncFromServer()` retoma as exclusões pendentes **antes** de listar. E,
por garantia, ainda filtra da listagem qualquer id que continue na fila: se o
`DELETE` falhar de novo enquanto o `GET` funciona, o perfil aparece na
listagem e não pode ser semeado. Dois testes cobrem os dois casos.

Não é um caso hipotético: "removi alguém e o app trouxe de volta sozinho" é o
tipo de bug que ninguém reporta direito, porque parece coisa da cabeça de quem
viu.

---

## 3. Uma consequência na tela que talvez interesse

Um participante semeado tem perfil de voz no servidor e **nenhum WAV neste
aparelho**. A tela perguntava `hasVoiceSample` (existe arquivo local?), que
depois da reinstalação responderia "não" para todo mundo e mandaria o usuário
regravar voz que já estava cadastrada — desfazendo o ganho.

Agora a pergunta é `hasVoiceProfile` (`voiceProfileSynced || hasVoiceSample`),
e a lista de participantes ganhou um quarto estado:

| Estado | Rótulo |
|---|---|
| sem voz | Sem amostra de voz |
| WAV local, não enviado | Amostra gravada — não sincronizada |
| WAV local, enviado | ✓ Amostra sincronizada |
| **só no servidor** (semeado) | **✓ Voz cadastrada no servidor** |

O último é o novo. Ele existe para o usuário entender por que aquela pessoa
está lá com a voz pronta sem ele ter gravado nada neste aparelho.

---

## 4. Sobre o `name` nulo

Tratado. O app sempre manda o `name` no `POST .../voice-samples`, então isso
não acontece com perfis criados por ele — mas outro cliente pode deixar em
branco, e uma lista de ids crus não dá para mostrar a ninguém.

O fallback é `Participante <últimos 4 dígitos do id>`, para dois perfis sem
nome não ficarem indistinguíveis na tela. O `participant_id`, que é o que
importa recuperar, é preservado intacto em qualquer caso.

Não há tela de renomear participante hoje, então um perfil sem nome fica com o
rótulo até alguém regravar a amostra por ele (o que manda o nome). Como não
deve acontecer na prática, não achamos que valha uma tela nova; se aparecer no
uso real, a gente revisita.

---

## 5. Sobre a heurística dos jobs

Concordamos em deixar fora, e o furo que vocês apontaram é decisivo:
**cadastrar todo mundo antes da primeira reunião é o fluxo normal do app** —
é literalmente o que a tela de participantes existe para fazer, e o que o
diálogo "Nenhum participante cadastrado / Cadastrar agora" empurra o usuário a
fazer antes de gravar qualquer coisa.

Então não é um caso raro: seria a maioria dos perfis de um usuário novo, todos
classificados como resto de instalação anterior. Apagar biometria válida em
massa. Bom que ficou fora, e bom que ficou registrado o porquê.

---

## 6. Zero órfãos hoje

Registrado, e é a melhor notícia das duas rodadas: a rota entra antes da
primeira gravação de voz de uma pessoa real. Nada a recuperar, nenhuma faxina
retroativa, nenhuma decisão sobre o que fazer com dado ambíguo de origem
desconhecida.

Do lado do app, os três perfis do E2E (`p-ana`, `p-bruno`, `p-carla`) estão
sob outro `user_id`, então não aparecem para conta nenhuma do teste conjunto —
a listagem é escopada, e isso também está coberto por teste do nosso lado.

---

## 7. Resumo

| Item | Situação |
|---|---|
| Semear cadastro em instalação nova | ✅ `seedFromServerIfEmpty`, na tela inicial |
| Listagem no lugar do `voice-profile` um a um | ✅ uma chamada; o código antigo saiu |
| Falha de rede ≠ ausência | ✅ mantido, com teste |
| Exclusão pendente antes da listagem | ✅ ordem + filtro, com dois testes |
| `name` nulo | ✅ fallback com sufixo do id; id preservado |
| Heurística dos jobs | ✅ descartada, com o motivo registrado |
| Teste conjunto | ⏳ ordem acertada; **data ainda a confirmar** |

O único item em aberto entre os dois lados continua sendo a data do teste
conjunto. Nada do que entrou nesta rodada depende dela, e nada dela depende
desta rodada — mas a lista de coisas integradas e nunca exercitadas contra o
servidor ganhou mais uma rota hoje.
