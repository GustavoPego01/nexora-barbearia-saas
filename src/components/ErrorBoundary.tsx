import { Component, type ReactNode } from 'react'

export class ErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false }

  static getDerivedStateFromError() {
    return { failed: true }
  }

  render() {
    if (this.state.failed) {
      return <main className="startup"><h1>Não foi possível abrir esta página.</h1>
        <p>Tente carregar o sistema novamente.</p>
        <button onClick={() => window.location.reload()}>Recarregar</button></main>
    }
    return this.props.children
  }
}
