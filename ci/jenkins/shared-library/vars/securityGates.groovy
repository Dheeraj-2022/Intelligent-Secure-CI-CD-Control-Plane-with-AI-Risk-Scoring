def evaluate(Map config) {
    def coverage = config.coverage.toFloat()
    def criticalVulns = config.criticalVulns.toInteger()
    def riskScore = config.riskScore.toFloat()
    
    def gates = [
        [name: 'Code Coverage', passed: coverage >= 80, value: "${coverage}%"],
        [name: 'Critical Vulnerabilities', passed: criticalVulns == 0, value: criticalVulns],
        [name: 'Risk Score', passed: riskScore < 0.7, value: riskScore]
    ]
    
    echo """
    ╔═══════════════════════════════════════════════════════════╗
    ║                  SECURITY GATES REPORT                    ║
    ╠═══════════════════════════════════════════════════════════╣
    """
    
    def allPassed = true
    gates.each { gate ->
        def status = gate.passed ? '✅ PASS' : '❌ FAIL'
        echo "║ ${gate.name.padRight(30)} ${status.padLeft(10)} (${gate.value}) ║"
        allPassed = allPassed && gate.passed
    }
    
    echo """
    ╚═══════════════════════════════════════════════════════════╝
    """
    
    if (!allPassed) {
        error "Security gates failed. Build blocked."
    }
    
    return allPassed
}

return this