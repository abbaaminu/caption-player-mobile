import 'package:flutter/material.dart';

import '../config/app_config.dart';

class PaywallOverlay extends StatelessWidget {
  final TextEditingController controller;
  final String statusMessage;
  final VoidCallback onActivate;
  final VoidCallback onOpenPricing;
  final bool isLoading;

  const PaywallOverlay({
    super.key,
    required this.controller,
    required this.statusMessage,
    required this.onActivate,
    required this.onOpenPricing,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.96),
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Your 30-Minute Free Caption Trial Has Expired.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Choose a monthly plan or lifetime pass to keep watching.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                    ),
                    onPressed: onOpenPricing,
                    child: const Text(AppConfig.monthlyPlanLabel),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A8870),
                    ),
                    onPressed: onOpenPricing,
                    child: const Text(AppConfig.lifetimePlanLabel),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Paste your Activation License Key...",
                    hintStyle: TextStyle(color: Colors.white30),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: onActivate,
                      child: const Text("Activate Player"),
                    ),
              if (statusMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  statusMessage,
                  style: const TextStyle(color: Colors.amber, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
