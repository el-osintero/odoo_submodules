#!/usr/bin/env bash
# ——— Script para actualizar submódulos de repositorios ———
# ——— Descripción ———
# Echo por Milton Procel M. 
set -euo pipefail

# ——— Parámetros ———
VERSION="16.0"
FECHA=$(date +"%Y_%m_%d")
NEW_BRANCH_SUFFIX="MP_${VERSION}_Actualizacion_submodulos"
GITHUB_ORG="TRESCLOUD"
GITHUB_TOKEN= #Token Aqui
declare -a FALLIDOS=()
declare -a PRS_CREADOS=()

# Lista de repositorios a procesar
REPOS_A_PROCESAR=(
    "i001531"
    "packworld"
    "i001324"
    "i001385"
    "i001308"
    "i001405"
)

# ——— Crear PR por API REST (simple) ———
crear_pr() {
  local repo=$1
  local base=$2
  local head_branch=$3

  local title="[IMP][PM][V${VERSION}] Actualizar submódulos"
  local body="Actualizacion de Submodulos"
  local head="${head_branch}" 
  local url="https://api.github.com/repos/${GITHUB_ORG}/${repo}/pulls"

  # Payload simple
  local payload
  payload=$(printf '{"title":"%s","head":"%s","base":"%s","body":"%s"}' \
    "$title" "$head" "$base" "$body")

  local resp
  resp="$(
    curl -sS -X POST \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url" \
      -d "$payload"
  )"

  # Extraer html_url o fallar mostrando mensaje
  local pr_url
  pr_url="$(python3 - <<'PY' "$resp"
import json, sys
data = json.loads(sys.argv[1])

if "html_url" in data:
    print(data["html_url"])
    sys.exit(0)

# Si hubo error, imprime mensaje
msg = data.get("message", "Error desconocido")
errs = data.get("errors")
print(f"ERROR: {msg}")
if errs:
    print(errs)
sys.exit(1)
PY
  )" || {
    echo "❌ No se pudo crear PR en ${repo}. Respuesta:"
    echo "$resp"
    return 1
  }

  PRS_CREADOS+=("${pr_url}")
  echo "✅ PR creado: ${pr_url}"
  return 0
}

# ——— Función de actualizar submódulos ———
procesar_repo() {
    local REPO=$1
    local REMOTE_URL="git@github.com:${GITHUB_ORG}/${REPO}.git"

    if [ ! -d "$REPO" ]; then
        echo "📥 '$REPO' no existe. Clonando desde ${REMOTE_URL} (branch ${VERSION})..."
        git clone --recurse-submodules --branch "$VERSION" "$REMOTE_URL" "$REPO" \
          || { echo "❌ git clone falló para $REPO"; return 1; }
    fi
    if [ ! -d "$REPO/.git" ]; then
        echo "❌ '$REPO' existe pero no es un repo git (no hay .git)."
        return 1
    fi

    pushd "$REPO" > /dev/null    
    set +e                     

    git fetch origin \
      || { echo "❌ git fetch falló en $REPO"; popd > /dev/null; return 1; }

    git checkout "$VERSION" \
      || { echo "❌ No existe la rama $VERSION en $REPO"; popd > /dev/null; return 1; }

    git pull origin "$VERSION" \
      || { echo "❌ git pull falló en $REPO";        popd > /dev/null; return 1; }

    git submodule update --remote --recursive --force \
      || { echo "❌ submodule update falló en $REPO"; popd > /dev/null; return 1; }

    git add TRESCLOUD/*\
      || { echo "❌ git add falló en $REPO";          popd > /dev/null; return 1; }

    # Si no hay nada staged, salimos con éxito
    if git diff --cached --quiet; then
      echo "✔️  No hay cambios en submódulos de $REPO"
      set -e
      popd > /dev/null 
      return 0
    fi

    local BRANCH="${FECHA}/${NEW_BRANCH_SUFFIX}"
    git show-ref --verify --quiet "refs/heads/$BRANCH" \
      && git checkout "$BRANCH" \
      || git checkout -b "$BRANCH" \
      || { echo "❌ crear rama falló en $REPO"; popd > /dev/null; return 1; }

    git commit -m "[IMP][PM][V$VERSION] Actualizar submódulos" \
      || { echo "❌ git commit falló en $REPO"; popd > /dev/null; return 1; }

    git push origin "$BRANCH" \
      || { echo "❌ git push falló en $REPO"; popd > /dev/null; return 1; }

    crear_pr "$REPO" "$VERSION" "$BRANCH" \
    || { echo "❌ Crear PR falló en $REPO"; popd > /dev/null; return 1; }

    set -e  
    popd > /dev/null 

    echo "✅ $REPO procesado con éxito."
    return 0
}

# ——— Main Function ———
for REPO in "${REPOS_A_PROCESAR[@]}"; do
  echo
  echo "———————— Procesando $REPO ————————"
  if ! procesar_repo "$REPO"; then
    FALLIDOS+=("$REPO")
  fi
done

# ——— PR creados ———
if [ "${#PRS_CREADOS[@]}" -gt 0 ]; then
  echo "🔗 PRs creados:"
  for pr in "${PRS_CREADOS[@]}"; do
    echo "   • $pr"
  done
else
  echo "ℹ️  No se crearon PRs (posiblemente no hubo cambios staged)."
fi

# ——— Repos fallados ———
if [ "${#FALLIDOS[@]}" -gt 0 ]; then
  echo
  echo "⚠️  Estos repos fallaron y necesitan revisión manual:"
  for R in "${FALLIDOS[@]}"; do
    echo "   • $R"
  done
  exit 1
else
  echo
  echo "🎉 Todos los repos se actualizaron correctamente."
  exit 0
fi
